# RippleSpark: Ripple-65B on 2x DGX Spark (GB10) with TensorFold

Ricursive's Ripple-65B-Preview (65B dense; 80 layers, four 1,024-token sliding-window layers to every full-attention
layer) served across two DGX Sparks with tensor parallelism, from our own
EXL3 quantisation, on TensorFold 1.2.3, with Ricursive's DFlash2 drafter.

5.0 bpw model, 1M context window, DFlash2 on. 

## Running it

Two GB10 Sparks joined by their CX7 ports, Docker with the NVIDIA runtime on both, SSH from the head
to the worker. Ports: 8888 (API), 29681 (between the Sparks). Set `WORKER` (user@address) and `MASTER` (the
head's CX7 address) in `scripts/local.sh`.

```bash
scripts/prepare.sh        # the image, built on the head and copied to the worker
scripts/zig_prepare.sh    # TensorFold v1.2.3 + patches-zig/, compiled in Docker, copied to the worker
scripts/fetch_pack.sh     # the 5.0 model and the drafter from Hugging Face (pinned), on both Sparks, verified
scripts/start.sh          # OpenAI API on :8888, model id Ripple-65B-Preview
scripts/stop.sh
```

The model: [ajensenwaud/Ripple-65B-Preview-exl3-5.0bpw](https://huggingface.co/ajensenwaud/Ripple-65B-Preview-exl3-5.0bpw).
To make it yourself: `scripts/quantise.sh 5.0` (about 6 h on one GB10).

Settings in `scripts/config.sh` (override in `scripts/local.sh`): `PACK=5.0|6.0`, `CONTEXT=1048576`, `STREAMS=1`
(or `STREAMS=4 CONTEXT=262144` for four agents at once), `DRAFTER=1|0`.

## Four Sparks

The same scripts serve Ripple across four Sparks with TP=4, each on one CX7 link to a QSFP switch with RoCE. In
`scripts/local.sh`, name the three workers in rank order instead of `WORKER`, and set the switch's GID index:

```bash
WORKERS="user@192.0.2.2 user@192.0.2.3 user@192.0.2.4"
MASTER=192.0.2.1
NCCL_GID=5                        # RoCE v2 over IPv4 on the switch (3 on a direct cable)
RANK_HCAS="- mlx5_0,mlx5_2 - -"   # only if a Spark names its RoCE devices otherwise
```

Four Sparks also use ports 29700-29707 for the small gathers. One stream of 1M tokens, `STREAMS=8 CONTEXT=262144`
or `STREAMS=16 CONTEXT=131072`.

Patches 0011-0015 speed up prompt reading and many streams at once, on two Sparks as well as four. With them, four
Sparks decode 17.6 tok/s plain and 57.4 with DFlash2 on one coding stream, 229 tok/s in total across 16 streams,
and read prompts at about 1,100 tok/s (a 1M-token prompt in 47 min); two Sparks read at about 610 tok/s. At greedy
decoding, four Sparks give byte-identical replies to two. Details and measurements:
[zrresearch/ripplespark-4dgx](https://github.com/zrresearch/ripplespark-4dgx).

## Models

Same source and exllamav3 settings (`-cr 250 -cc 2048`, mul1 codebook, head 8 bits, embedding 16 bits); only the
bitrate differs.

| Model | Size | Weights a Spark | Plain decode, 1 stream |
|---|---|---|---|
| **5.0 bpw (default)** | 39 GB | 19.8 GiB | 9.9 tok/s |
| 6.0 bpw | 47 GB | 23.5 GiB | 8.8 tok/s |

## Quality

Against the original BF16 weights (96 rows of 2,048 tokens), and through the server on two Sparks (temperature 0.6,
the same items for both models; greedy decoding can loop in long reasoning).

| | 5.0 bpw | 6.0 bpw | BF16 |
|---|---|---|---|
| Same top token as BF16 | 97.9 % | 98.9 % | 100 % |
| Wikitext-2 perplexity (64 x 2048) | 9.270 | 9.248 | 9.245 |
| GSM8K (500) | 97.4 % | 97.6 % | |
| MMLU-Pro (first 40) | 75.0 % | 77.5 % | |

The two models tie on both tasks (McNemar p = 1.0). 6.0 is indistinguishable from BF16 on perplexity; 5.0 is 0.27 %
above it. On MMLU-Pro, Ripple reasons ~6,800 tokens an item and 10 % of replies hit the
30K-token cap on both models.

## Speed (5.0 model)

One stream, greedy, 512-token replies:

| Task | Plain decode | DFlash2 | Speed-up |
|---|---|---|---|
| coding | 9.9 tok/s | 46.6 tok/s | 4.7x |
| agent tool call | 9.9 | 31.7 | 3.2x |
| chat | 9.9 | 19.2 | 1.9x |
| 4 streams together (4 x 256K, total) | 35.6 | 57.4 | 1.6x |

Long prompts (spark-bench, cold, DFlash2 on):

| Prompt | Prompt reading | First token | Decode |
|---|---|---|---|
| 4K | 410 tok/s | 9.7 s | 24.8 tok/s |
| 64K | 381 tok/s | 2.8 min | 17.7 tok/s |
| 256K | 292 tok/s | 14.6 min | 8.0 tok/s |
| 1M | 156 tok/s | 1 h 48 min | 3.7 tok/s (plain) |

## Credits and licence

Thanks to Ricursive for Ripple-65B-Preview and its DFlash2 drafter; Ash Hart ([@ashxhart](https://x.com/ashxhart))
for [TensorFold](https://github.com/ashhart/TensorFold); BobClawblaw for the Ripple config in TensorFold PR #2231
(patch 0001); auryn-macmillan for exllamav3's Ripple support (`feat/ricursive`), which made the packs; turboderp for
[exllamav3](https://github.com/turboderp-org/exllamav3); Mia AI Lab for the TensorFold CUDA base image. Evaluation
data: GSM8K (MIT), MMLU-Pro (MIT), WikiText-2 (CC BY-SA 3.0).

Recipe code: BSD 3-Clause. `patches-zig/` keep TensorFold's Apache-2.0. The model is Apache-2.0.

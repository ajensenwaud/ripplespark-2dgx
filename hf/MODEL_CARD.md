---
license: apache-2.0
language:
- en
base_model: ricursiveAI/Ripple-65B-Preview
base_model_relation: quantized
pipeline_tag: text-generation
library_name: exllamav3
tags:
- exl3
- ricursive
- ripple
- tensorfold
- dgx-spark
---

# Ripple-65B-Preview, EXL3 5.0 bpw

[ricursiveAI/Ripple-65B-Preview](https://huggingface.co/ricursiveAI/Ripple-65B-Preview) (65B dense) quantised to
EXL3 at 5.0 bits per weight, made to run across two NVIDIA DGX Sparks (GB10) with tensor parallelism at the model's
full 1M-token context. The recipe that serves it, with every measurement below as raw JSON:
[ajensenwaud/ripplespark-2dgx](https://github.com/ajensenwaud/ripplespark-2dgx).

| | |
|---|---|
| Weights | 39 GB, 5 shards (19.8 GiB a Spark at TP=2) |
| Bitrate | 5.0 bpw (excluding head); head 8 bpw; embedding 16 bpw |
| Conversion | exllamav3 1.6.6 + `feat/ricursive` @ `d71a6644`, `-b 5.0 -hb 8 -cr 250 -cc 2048 -cb mul1`, source @ `da94cc01` |
| Drafter | not included: use Ricursive's BF16 [Ripple-65B-Preview-DFlash2](https://huggingface.co/ricursiveAI/Ripple-65B-Preview-DFlash2) @ `35609b3b` |

## Quality

Against the original BF16 weights (96 rows of 2,048 tokens), and served on two Sparks with the recipe's engine
(temperature 0.6, the same items for both packs).

| | 5.0 bpw (this) | 6.0 bpw | BF16 |
|---|---|---|---|
| Same top token as BF16 | 97.9 % | 98.9 % | 100 % |
| Wikitext-2 perplexity (64 x 2048) | 9.270 | 9.248 | 9.245 |
| GSM8K (500) | 97.4 % | 97.6 % | |
| MMLU-Pro (first 40) | 75.0 % | 77.5 % | |

The packs tie on both tasks (McNemar p = 1.0). MMLU-Pro is a 40-item check: 10 % of replies hit the 30K-token cap.

## Speed (two DGX Sparks, the recipe, one stream)

| Task | Plain decode | With DFlash2 |
|---|---|---|
| coding | 9.9 tok/s | 46.6 tok/s |
| agent tool call | 9.9 | 31.7 |
| chat | 9.9 | 19.2 |

## Use

With the recipe (two Sparks): `scripts/fetch_pack.sh` then `scripts/start.sh`. The pack needs exllamav3's
`feat/ricursive` branch (auryn-macmillan) for the value residual; upstream exllamav3 1.6.6 cannot load it.

## Acknowledgements

Ricursive for the model and the DFlash2 drafter; auryn-macmillan for exllamav3's Ripple support and turboderp for
exllamav3, which made this pack; Ash Hart for TensorFold, the engine it was evaluated on. Evaluation data: GSM8K
(MIT), MMLU-Pro (MIT), WikiText-2 (CC BY-SA 3.0).

## Licence

Apache-2.0, as the source model.

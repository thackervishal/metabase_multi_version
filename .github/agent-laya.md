# Laya (local decision model for ticket RCA)

Laya is a small open-source encoder model (Apache-2.0, 421M parameters). It answers typed questions about a text in one forward pass and never generates text. It is a free local alternative to JEV, for cheap routing, filtering, and duplicate checks that would otherwise cost LLM tokens. It does not replace reasoning.

## Run it

- `make laya-up` builds the image on first use, starts the container, and waits until it is healthy. The first start downloads PyTorch (a few GB) and the model weights into the `laya_laya_hf` volume.
- `make laya-stop` stops it. `make laya-down` removes the container and keeps the weights. `make done` also stops it.
- `bash scripts/laya.sh check` confirms the GPU is in use, not a silent CPU fallback. `bash scripts/laya.sh logs` shows the last log lines.
- The files are `compose/laya/Dockerfile`, `compose/laya/compose.yml`, and `scripts/laya.sh`.

## Settings that matter

- The server is published on `127.0.0.1:${LAYA_PORT:-8787}` only. Port 8787 is outside the Windows excluded port ranges on the machine where this was written. Those ranges change, so check `netsh interface ipv4 show excludedportrange protocol=tcp` if the bind fails.
- Auth: `laya.sh` writes a random key to `.state/laya-api-key` (gitignored). Clients send `Authorization: Bearer <key>`. `laya-serve` reads only `LAYA_API_KEY`, not `LAYA_API_KEY_FILE` (that variable works only in upstream's own Docker entrypoint). So `compose/laya/entrypoint.sh` loads the key from the mounted secret file and refuses to start without one. Confirmed live: no key and a wrong key return 401, the right key returns 200. Don't "simplify" this to `LAYA_API_KEY_FILE` alone, because the server then runs with no auth and still returns 200.
- Pins: `laya==0.4.8`, `torch==2.14.0`, CUDA wheel index `cu130` (needs driver 580 or newer). Blackwell GPUs (RTX 50 series) need a CUDA 12.8 or newer wheel. Override with `LAYA_VERSION`, `LAYA_TORCH_VERSION`, `LAYA_TORCH_INDEX`.
- Only the English checkpoint loads by default (`LAYA_MODELS=english`, `LAYA_MAX_LOADED=1`). It reads 512 tokens. The multilingual checkpoint reads 1,024 (up to 8,192 with `max_len`) and handles other languages. For non-English tickets or long text, set `LAYA_MODELS=english,multilingual` and `LAYA_MAX_LOADED=2` in `env/common.env`. The English checkpoint is unreliable on non-Latin scripts.

## API

- `POST /v1/systemone` with `{"state": ..., "questions": {...}}`.
- `POST /v1/systemone/batch` with `{"states": [...], "questions": {...}}`. Maximum 64 states per call.
- `GET /health`.
- Question types: `choice` (with `criteria`), `score`, `noul` (yes/no).

## Known limits (from the project's own model card)

- Zero-shot accuracy is weak on `score` and `noul` questions. For yes/no, use a two-option `choice` instead of `noul`.
- Probabilities are overconfident. Use them to rank, never as proof, and fit thresholds on your own data.
- Weak with many options (77-label benchmark: 0.425, against 0.870 for JEV).
- The English checkpoint fails on non-Latin scripts. The router picks the multilingual one when it detects another language.

## Customer data

Laya runs on this machine only, so ticket text sent to it does not leave the machine.

## Verified on this machine (RTX 5080 Laptop, driver 592)

- The cu130 build runs on the GPU: `laya.sh check` reports CUDA available. The English checkpoint uses about 2 GB of VRAM.
- Image size is about 3.2 GB. A warm single request takes about 40 ms. The first request takes about 600 ms.
- The startup log warns that the checkpoint ships invalid temperatures and clamps them. This agrees with the limits above: treat confidence as a ranking signal only.

# Local Laya decision-model server (CUDA). Thin wrapper around the PyPI package;
# upstream ships no GPU image. Weights are NOT baked in: they download from
# Hugging Face on first start into the laya_hf volume.
FROM python:3.12-slim

# TORCH_INDEX must match a CUDA build your host driver supports (cu130 needs
# driver >= 580, and Blackwell GPUs such as the RTX 50 series need cu128+).
ARG TORCH_VERSION=2.14.0
ARG TORCH_INDEX=cu130
ARG LAYA_VERSION=0.4.8

RUN useradd --create-home --uid 10001 laya \
    && mkdir -p /home/laya/.cache/huggingface \
    && chown -R laya:laya /home/laya

RUN pip install --no-cache-dir --index-url "https://download.pytorch.org/whl/${TORCH_INDEX}" "torch==${TORCH_VERSION}" \
    && pip install --no-cache-dir "laya[serve]==${LAYA_VERSION}"

# Strip CRs in case git checked the script out with Windows line endings.
COPY entrypoint.sh /usr/local/bin/laya-entrypoint
RUN sed -i 's/\r$//' /usr/local/bin/laya-entrypoint && chmod 755 /usr/local/bin/laya-entrypoint

USER laya
ENV HF_HOME=/home/laya/.cache/huggingface \
    PYTHONUNBUFFERED=1

EXPOSE 8000
ENTRYPOINT ["laya-entrypoint"]
CMD ["laya-serve"]

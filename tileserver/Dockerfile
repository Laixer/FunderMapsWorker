FROM ghcr.io/maplibre/martin:1.12.0

# Noto Sans TTFs (OFL) — Martin generates glyph PBFs from these and serves
# them at /font/{fontstack}/{range}. Pinned to an openmaptiles/fonts
# commit for reproducible builds. Latin/Cyrillic/Greek coverage is enough
# for NL labels; extend with more Noto scripts if tofu ever shows up.
ADD --chmod=644 https://raw.githubusercontent.com/openmaptiles/fonts/0bcd6431ec82fbb74b3a5b697ce315ebf795ad8e/noto-sans/NotoSans-Regular.ttf /fonts/
ADD --chmod=644 https://raw.githubusercontent.com/openmaptiles/fonts/0bcd6431ec82fbb74b3a5b697ce315ebf795ad8e/noto-sans/NotoSans-Bold.ttf /fonts/
ADD --chmod=644 https://raw.githubusercontent.com/openmaptiles/fonts/0bcd6431ec82fbb74b3a5b697ce315ebf795ad8e/noto-sans/NotoSans-Italic.ttf /fonts/

COPY config.yaml /config.yaml
COPY styles/ /styles/
COPY sprites/ /sprites/

CMD ["--config", "/config.yaml"]

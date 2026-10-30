# AI Radio

The code in this repository is presented in https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/

It is adapted from original code from the [AzuraCast](https://www.azuracast.com/) community and in particular code from [@gAlleb](https://github.com/gAlleb).

It builds a video radio with an automated AI DJ inserted every 4 tracks. The DJ text is written by Claude and read by OpenAI text-to-speech.

To run:
* Install liquidsoap `2.5.x`
* Create a `config.liq` with the following content:
```liquidsoap
anthropic_api_key = "sk-ant-..."
openai_api_key = "sk-..."
```
* Place video files in `background/`
* Place audio files in `audio/`

Then run `liquidsoap main.liq`. The HLS stream is written to `hls/`.

Files:
* `main.liq`: wiring and output
* `dj.liq`: AI DJ (Claude prompt, speech synthesis, scheduling)
* `overlay.liq`: video canvas UI

# AI Radio

The code is in this repository is presented in https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/

It builds a video radio with an automated AI DJ inserted every 4 tracks.

To run:
* Install or build locally a version of liquidsoap `2.3.x` (current `main` branch as of writting) or the latest stable `2.2.x` release (preferably `2.2.4` or later) and backport the APIs as explained in the blog post
* Create a `config.liq` with the following content:
```liquidsoap
openai_api_key = "aabbccdd"
```
* Place video files in `background/`
* Place audio files in `audio/`

Next: run the script!

For `main`/`v2.3.x`, you can run the top-level `main.liq` script. For `v2.2.x` you can run `v2.2.x/main.liq`.

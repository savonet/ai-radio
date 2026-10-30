%include "config.liq"
%include "dj.liq"
%include "overlay.liq"

base_dir = path.dirname(argv(0))

music = playlist(path.concat(base_dir, "audio"), prefetch=2)

radio = ai_dj(every=4, music)

radio =
  video_overlay(
    font=path.concat(base_dir, "MesloLGS NF Bold.ttf"),
    background_dir=path.concat(base_dir, "background"),
    radio
  )

enc =
  %ffmpeg(
    format = "mpegts",
    %audio(codec = "aac", b = "192k"),
    %video(codec = "libx264", preset = "ultrafast", g = 50)
  )

output.file.hls(
  segment_duration=2.,
  path.concat(base_dir, "hls"),
  [("radio", enc)],
  mksafe(radio)
)

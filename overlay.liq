# Video UI drawn on a 10k virtual canvas: background videos, station name,
# now-playing title/artist, cover art, countdown and progress bar.
# Entry point: `video_overlay(~font, ~background_dir, radio)`.

let {px, vw, rem, width, height} = video.canvas.virtual_10k.actual_4k

video.frame.width := width
video.frame.height := height

def video_overlay(~font, ~background_dir, radio) =
  meta = ref([])
  radio.on_metadata(synchronous=true, fun (m) -> meta := m)

  def progress() =
    d = radio.duration()
    d > 0. ? radio.elapsed() / d : 0.
  end

  def remaining() =
    t = radio.remaining()
    seconds = string.of_int(digits=2, int(t mod 60.))
    minutes = string.of_int(digits=2, int(t / 60.))
    "#{minutes}:#{seconds}"
  end

  def box(~color=0xfcb900, ~alpha=1., ~x, ~y, ~width, ~height, s) =
    video.add_rectangle(
      color=color, alpha=alpha, x=x, y=y, width=width, height=height, s
    )
  end

  def text(~color=0xfcb900, ~size, ~x, ~y, t, s) =
    video.add_text(
      color=color, font=font, speed=0, x=x @ px, y=y @ px, size=size @ rem, t, s
    )
  end

  def shadowed_text(~color, ~size, ~x, ~y, t, s) =
    s = text(color=0x000000, size=size, x=x, y=y + 15, t, s)
    text(color=color, size=size, x=x, y=y, t, s)
  end

  v = playlist(background_dir)

  v =
    box(
      color=0x333333,
      alpha=0.4,
      x=4609 @ px,
      y=234 @ px,
      width=5468 @ px,
      height=429 @ px,
      v
    )
  v =
    shadowed_text(
      color=0xfcb900, size=2.15, x=4687, y=250, "Teardown The List Jockey", v
    )

  v =
    box(
      color=0x333333,
      alpha=0.4,
      x=0 @ px,
      y=4375 @ px,
      width=1. @ vw,
      height=960 @ px,
      v
    )
  v = box(alpha=0.7, x=0 @ px, y=5015 @ px, width=1. @ vw, height=15 @ px, v)
  v = box(x=210 @ px, y=2554 @ px, width=1609 @ px, height=1609 @ px, v)

  def field(name) =
    fun () -> list.assoc(default="", name, meta())
  end

  v = text(size=1.5, x=234, y=4437, field("title"), v)
  v = text(size=1.5, x=234, y=4710, field("artist"), v)
  v =
    text(color=0xcccccc, size=1., x=234, y=5039, {"Next in #{remaining()}"}, v)

  v =
    box(
      x=0 @ px, y=5285 @ px, width={progress() @ vw}, height=50 @ px, v
    )

  video.add_cover(
    x=234 @ px,
    y=2578 @ px,
    width=1562 @ px,
    height=1562 @ px,
    default="./default-cover.jpg",
    source.mux.video(video=v, radio)
  )
end

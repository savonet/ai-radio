%include "config.liq"

base_dir = path.dirname(argv(0))
audio_dir = path.concat(base_dir, "audio")
background_dir = path.concat(base_dir, "background")
hls_dir = path.concat(base_dir, "hls")
font = path.concat(base_dir, "MesloLGS NF Bold.ttf")

let {px, vw, vh, rem, width, height} = video.canvas.virtual_10k.actual_720p

video.frame.width := width
video.frame.height := height

## AI functions

def mk_prompt(old, new) =
  old =
    list.map(
      fun (m) ->
        begin
          title = m["title"]
          artist = m["artist"]
          "#{title} by #{artist}"
        end,
      old
    )

  old =
    string.concat(
      separator=
        ", ",
      old
    )

  new_title = new["title"]
  new_artist = new["artist"]

  new =
    "#{new_title} by #{new_artist}"

  "You are a radio DJ, you speak in the style of the old 50s early rock'n'roll \
   DJs. The following songs were just played: #{old}. Next playing is #{new}. \
   Can you describe the musical characteristics of each song that ended and how \
   they connect with each other? Then introduce the next song. Make sure to \
   include style, year, instruments and cultural context and anecdotes and fun \
   facts. Limit your response to 200 words and make sure that it sounds \
   entertaining and fun."
end

def generate_speech(prompt) =
  let {choices = [{message = {content}}]} =
    openai.chat(
      key=openai_api_key,
      [
        {
          role="system",
          content=
            "You are a helpful assistant."
        },
        {role="user", content=prompt}
      ]
    )

  tmp_file = file.temp("dj", ".mp3")

  on_data = file.write.stream(tmp_file)

  openai.speech(key=openai_api_key, voice="onyx", on_data=on_data, content)

  request.create(
    "annotate:title=\"AI DJ\":tmp:#{tmp_file}"
  )
end

## Audio setup

next_song = ref([])
def check_next(r) =
  ignore(request.resolve(r))
  request.read_metadata(r)
  next_song := request.metadata(r)
  true
end

radio = playlist(audio_dir, prefetch=2, check_next=check_next)

append_queue = request.queue()

past_songs = ref([])

def process_dj_metadata(m) =
  past_songs := [...past_songs(), m]

  if
    list.length(past_songs()) == 4
  then
    songs_history = past_songs()
    past_songs := []
    prompt = mk_prompt(songs_history, next_song())

    thread.run({append_queue.push(generate_speech(prompt))})
  end
end

radio = source.on_metadata(radio, process_dj_metadata)

radio = fallback(track_sensitive=true, [append_queue, radio])

current_title = ref("")
current_artist = ref("")

def update_current_song(m) =
  current_title := m["title"]
  current_artist := m["artist"]
end
radio.on_metadata(update_current_song)

def position() =
  source.elapsed(radio) / source.duration(radio)
end

def remaining() =
  time = source.remaining(radio)
  seconds = string.of_int(digits=2, int(time mod 60.))
  minutes = string.of_int(digits=2, int(time / 60.))
  "#{minutes}:#{seconds}"
end

## Video setup

background = playlist(background_dir)

background =
  video.add_rectangle(
    color=0x333333,
    alpha=0.4,
    x=4609 @ px,
    y=234 @ px,
    width=5468 @ px,
    height=429 @ px,
    background
  )

def add_text_with_backdrop(~x, ~y, ~size, ~color, text) =
  background =
    video.add_text(
      color=0x000000,
      font=font,
      x=x @ px,
      y=(y + 15) @ px,
      size=size @ rem,
      text,
      background
    )

  video.add_text(
    color=color,
    font=font,
    x=x @ px,
    y=y @ px,
    size=size @ rem,
    text,
    background
  )
end

background =
  add_text_with_backdrop(
    x=4687,
    y=250,
    size=2.15,
    color=0xFCB900,
    "Teardown The List Jockey"
  )

background =
  video.add_rectangle(
    color=0x333333,
    alpha=0.4,
    x=0 @ px,
    y=4375 @ px,
    width=1. @ vw,
    height=960 @ px,
    background
  )

background =
  video.add_rectangle(
    color=0xfcb900,
    alpha=0.7,
    x=0 @ px,
    y=5015 @ px,
    width=1. @ vw,
    height=15 @ px,
    background
  )

background =
  video.add_rectangle(
    color=0xfcb900,
    x=210 @ px,
    y=2554 @ px,
    height=1609 @ px,
    width=1609 @ px,
    background
  )

background =
  video.add_text(
    color=0xFCB900,
    font=font,
    speed=0,
    x=234 @ px,
    y=4437 @ px,
    size=1.5 @ rem,
    current_title,
    background
  )

background =
  video.add_text(
    color=0xFCB900,
    font=font,
    speed=0,
    x=234 @ px,
    y=4710 @ px,
    size=1.5 @ rem,
    current_artist,
    background
  )

background =
  video.add_rectangle(
    color=0xfcb900,
    x=0 @ px,
    y=5285 @ px,
    height=50 @ px,
    width={position() @ vw},
    background
  )

background =
  video.add_text(
    size=rem(1.),
    x=234 @ px,
    y=5039 @ px,
    color=0xcccccc,
    font=font,
    {
      "Next in #{remaining()}"
    },
    background
  )

radio = source.mux.video(video=background, radio)

radio =
  video.add_cover(
    x=234 @ px,
    y=2578 @ px,
    width=1562 @ px,
    height=1562 @ px,
    default="./default-cover.jpg",
    radio
  )

enc =
  %ffmpeg(
    format = "mpegts",
    %audio(
      codec = "aac",
      samplerate = 44100,
      channels = 2,
      b = "192k",
      profile = "aac_low"
    ),
    %video(codec = "libx264", preset = "ultrafast", g = 50)
  )

streams = [("radio", enc)]

output.file.hls(segment_duration=2., hls_dir, streams, mksafe(radio))

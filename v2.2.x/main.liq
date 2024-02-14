%include "../config.liq"
%include "backports.liq"

base_dir = path.dirname(path.dirname(argv(0)))
audio_dir = path.concat(base_dir, "audio")
background_dir = path.concat(base_dir, "background")
hls_dir = path.concat(base_dir, "hls")
font =
  path.concat(
    base_dir,
    "MesloLGS NF Bold.ttf"
  )

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
    x=px(4609),
    y=px(234),
    width=px(5468),
    height=px(429),
    background
  )

def add_text_with_backdrop(~x, ~y, ~size, ~color, text) =
  background =
    video.add_text(
      color=0x000000,
      font=font,
      x=px(x),
      y=px((y + 15)),
      size=rem(size),
      text,
      background
    )

  video.add_text(
    color=color,
    font=font,
    x=px(x),
    y=px(y),
    size=rem(size),
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
    x=px(0),
    y=px(4375),
    width=vw(1.),
    height=px(960),
    background
  )

background =
  video.add_rectangle(
    color=0xfcb900,
    alpha=0.7,
    x=px(0),
    y=px(5015),
    width=vw(1.),
    height=px(15),
    background
  )

background =
  video.add_rectangle(
    color=0xfcb900,
    x=px(210),
    y=px(2554),
    height=px(1609),
    width=px(1609),
    background
  )

background =
  video.add_text(
    color=0xFCB900,
    font=font,
    speed=0,
    x=px(234),
    y=px(4437),
    size=rem(1.5),
    current_title,
    background
  )

background =
  video.add_text(
    color=0xFCB900,
    font=font,
    speed=0,
    x=px(234),
    y=px(4710),
    size=rem(1.5),
    current_artist,
    background
  )

background =
  video.add_rectangle(
    color=0xfcb900,
    x=px(0),
    y=px(5285),
    height=px(50),
    width={vw(position())},
    background
  )

background =
  video.add_text(
    size=rem(1.),
    x=px(234),
    y=px(5039),
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
    x=px(234),
    y=px(2578),
    width=px(1562),
    height=px(1562),
    default="./default-cover.jpg",
    radio
  )

enc =
  %ffmpeg(
    format = "mpegts",
    %audio(codec = "aac", b = "192k"),
    %video(codec = "libx264", preset = "ultrafast", g = 50)
  )

streams = [("radio", enc)]

output.file.hls(segment_duration=2., hls_dir, streams, mksafe(radio))

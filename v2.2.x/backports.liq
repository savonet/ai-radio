let video.canvas = ()

# Create a virtual canvas that can be used to return video position and sizes
# that are independent of the frame's dimensions.
# @category Source / Video processing
# @param ~virtual_width Virtual height, in pixels, of the canvas
# @param ~actual_size Actual size, in pixels, of the canvas
# @param ~font_size Font size, in virtual pixels.
# @method ~px Map a virtual size in pixel to the actual size.
# @method ~rem Map a fraction of the virtual font size into an actual font size
# @method ~vh Return a position in percent (as a value between `0.` and `1.`) \
#             of the canvas height
# @method ~vw Return a position in percent (as a value between `0.` and `1.`) \
#             of the canvas width
def video.canvas.make(~virtual_width, ~actual_size, ~font_size) =
  virtual_width = float(virtual_width)
  actual_height = float(actual_size.height)
  actual_width = float(actual_size.width)
  ratio = actual_width / virtual_width
  font_ratio = float(font_size) * ratio

  def px((v:int)) =
    int_of_float(float(v) * ratio)
  end

  def vh(v) =
    int_of_float(v * actual_height)
  end

  def vw(v) =
    int_of_float(v * (float(actual_width)))
  end

  def rem(v) =
    int_of_float(v * font_ratio)
  end

  {px=px, rem=rem, vw=vw, vh=vh, ...actual_size}
end

# Standard video canvas based off a `10k` virtual canvas.
# @category Source / Video processing
def video.canvas.virtual_10k =
  def make(width, height) =
    video.canvas.make(
      virtual_width=10000,
      actual_size={width=width, height=height},
      font_size=160
    )
  end

  {
    actual_360p=make(640, 360),
    actual_480p=make(640, 480),
    actual_720p=make(1280, 720),
    actual_1080p=make(1920, 1080),
    actual_1440p=make(2560, 1440),
    actual_4k=make(3840, 2160),
    actual_8k=make(7680, 4320)
  }
end

# Store and retrieve file covers using metadata. This returns a set of
# getter/setter methods that can be used to store and retrieve cover art.
# Typical usage is to set cover art in a `on_metadata` handler and retrieve
# it in a `video.add_image` operator. See `video.add_cover` for an implementation
# example.
# @category Metadata
# @flag extra
# @param ~default Default cover file when no cover is available
# @param ~mime_types Recognized mime types and their corresponding file extensions.
def file.cover.manager(
  ~id=null(),
  ~mime_types=[
    ("image/gif", "gif"),
    ("image/jpeg", "jpeg"),
    ("image/png", "png"),
    ("image/webp", "webp")
  ],
  ~default
) =
  id = string.id.default(id, default="cover")
  temp_dir = file.temp_dir("cover-manager")
  counter = ref(0)
  on_cleanup({file.rmdir(temp_dir)})

  last_cover_file = ref(default)
  current_cover_file = ref(default)

  def set_current_cover(filename) =
    last_cover = last_cover_file()
    last_cover_file := current_cover_file()
    current_cover_file := filename

    if
      last_cover != default
    then
      log.info(
        label=id,
        "Removing #{string.quote(last_cover)}"
      )
      file.remove(last_cover)
    end
  end

  def save_cover_to_file(cover) =
    mime = cover.mime
    extension = mime_types[mime]

    cover_file =
      if
        extension != ""
      then
        cover_file = path.concat(temp_dir, "#{id}_#{counter()}.#{extension}")
        ref.incr(counter)
        file.write(cover_file, data=cover)
        cover_file
      else
        null()
      end
    (cover_file, mime)
  end

  def extract_cover_from_metadata(_metadata) =
    filename = _metadata["filename"]
    log.info(
      label=id,
      "Extracting cover from #{string.quote(filename)}."
    )
    cover = metadata.cover(_metadata)
    let (cover_file, mime) =
      null.case(cover, {(null(), "")}, save_cover_to_file)

    next_cover =
      if
        cover == null()
      then
        log.important(
          label=id,
          "File #{string.quote(filename)} has no cover."
        )
        default
      elsif
        cover_file == null()
      then
        log.important(
          label=id,
          "File #{string.quote(filename)} has unknown mime type #{string.quote(mime)}."
        )
        default
      else
        cover_file = null.get(cover_file)
        log.important(
          label=id,
          "Cover for #{string.quote(filename)} saved to #{string.quote(cover_file)}."
        )
        cover_file
      end
    set_current_cover(next_cover)
  end

  current_cover_file.{set=extract_cover_from_metadata}
end

# Extract cover from the source's metadata and add it as a static image.
# @category Track / Video processing
# @flag extra
# @param ~id Force the value of the source ID.
# @param ~width Scale to width
# @param ~height Scale to height
# @param ~x x position.
# @param ~y y position.
# @param ~default Default cover file when no cover is available
# @param ~mime_types Recognized mime types and their corresponding file extensions.
def video.add_cover(
  ~width=null(),
  ~height=null(),
  ~x=getter(0),
  ~y=getter(0),
  ~mime_types=[
    ("image/gif", "gif"),
    ("image/jpeg", "jpeg"),
    ("image/png", "png"),
    ("image/webp", "webp")
  ],
  ~default,
  s
) =
  cover_file = file.cover.manager(mime_types=mime_types, default=default)
  s = source.on_metadata(s, cover_file.set)
  video.add_image(
    x=x, y=y, width=width, height=height, file=cover_file, s
  )
end

# Convert an int to string.
# @category String
# @param ~digits Minimal number of digits (pad with 0s on the left if necessary).
def string.of_int(~digits=0, n) =
  s = string(n)
  if
    string.length(s) >= digits
  then
    s
  else
    string.make(char_code=48, digits - string.length(s)) ^ s
  end
end

let error.openai = error.register("openai")

openai = ()

# @flag hidden
def parse_openai_error(ans, err) =
  try
    let json.parse (e : {error: {message: string, type: string}}) = ans

    e = e.error

    error.raise(
      error.openai,
      "#{e.type}: #{e.message}"
    )
  catch _ do
    error.raise(err)
  end
end

# Query ChatGPT API.
# @param ~base_url Base URL for the API query
# @param ~key OpenAI API key.
# @param ~model Language model.
# @param ~timeout Timeout for network operations in seconds.
# @param messages Messages initially exchanged.
# @category Internet
# @flag extra
def openai.chat(
  ~key,
  ~base_url="https://api.openai.com",
  ~model="gpt-3.5-turbo",
  ~timeout=null(30.),
  (
  messages:
  [
    {
      role: string,
      content: string,
      name?: string,
      tool_calls?: [
        {id: string, type: string, function: {name: string, arguments: string}}
      ],
      tool_call_id?: string
    }
  ]
  )
) =
  payload = {model=model, messages=messages}

  ans =
    http.post(
      data=json.stringify(payload),
      timeout=timeout,
      headers=
        [
          ("Content-Type", "application/json"),
          (
            "Authorization",
            "Bearer #{(key : string)}"
          )
        ],
      "#{base_url}/v1/chat/completions"
    )

  if
    ans.status_code != 200
  then
    error.raise(
      error.http,
      "#{ans.status_code}: #{ans.status_message}"
    )
  end

  try
    let json.parse (ans :
      {
        choices: [
          {
            finish_reason: string,
            index: int,
            message: {content: string, role: string}
          }
        ],
        created: int,
        model: string,
        object: string,
        usage: {completion_tokens: int, prompt_tokens: int, total_tokens: int}
      }
    ) = ans
    ans
  catch err : [error.json] do
    parse_openai_error(ans, err)
  end
end

# Generate speech using openai. Returns the encoded audio data.
# @param ~base_url Base URL for the API query
# @param ~key OpenAI API key.
# @param ~model Language model.
# @param ~timeout Timeout for network operations in seconds.
# @param ~voice The voice to use when generating the audio. Supported voices are `"alloy"`, `"echo"`, `"fable"`, `"onyx"`, `"nova"`, and `"shimmer"`
# @param ~response_format The format to audio in. Supported formats are: `"mp3"`, `"opus"`, `"aac"`, and `"flac"`.
# @param ~speed The speed of the generated audio. Select a value from `0.25` to `4.0`. `1.0` is the default.
# @params ~on_data Function executed when receiving the audio data.
# @category Internet
# @flag extra
def openai.speech(
  ~key,
  ~base_url="https://api.openai.com",
  ~model="tts-1",
  ~timeout=null(30.),
  ~voice,
  ~response_format="mp3",
  ~speed=1.,
  ~on_data,
  (input:string)
) =
  payload =
    {
      model=model,
      input=input,
      voice=(voice : string),
      response_format=response_format,
      speed=speed
    }

  ans =
    http.post.stream(
      data=json.stringify(payload),
      timeout=timeout,
      headers=
        [
          ("Content-Type", "application/json"),
          (
            "Authorization",
            "Bearer #{(key : string)}"
          )
        ],
      on_body_data=on_data,
      "#{base_url}/v1/audio/speech"
    )

  if
    ans.status_code != 200
  then
    error.raise(
      error.http,
      "#{ans.status_code}: #{ans.status_message}"
    )
  end
end

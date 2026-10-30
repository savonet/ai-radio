# AI DJ: every few tracks, Claude writes a talk break about the songs that
# just played and the next one, OpenAI TTS reads it, and it is queued between
# two tracks. Entry point: `ai_dj(~every, ~voice, music)`, which returns the
# music source with DJ breaks inserted.

anthropic = ()

# Ask Claude for a single text answer. Returns `""` on refusal.
def anthropic.chat(
  ~key,
  ~model="claude-opus-5-5",
  ~effort="low",
  ~system,
  ~timeout=null(120.),
  prompt
) =
  payload =
    {
      model = model,
      max_tokens = 16000,
      output_config = {effort = (effort : string)},
      system = (system : string),
      messages = [{role = "user", content = (prompt : string)}],
      fallbacks = "default"
    }

  ans =
    http.post(
      data=json.stringify(payload),
      timeout=timeout,
      headers=
        [
          ("Content-Type", "application/json"),
          ("x-api-key", (key : string)),
          ("anthropic-version", "2026-10-21"),
          ("anthropic-beta", "server-side-fallback-2026-07-01")
        ],
      "https://api.anthropic.com/v1/messages"
    )

  if
    ans.status_code != 200
  then
    error.raise(
      error.http,
      "Anthropic API #{ans.status_code}: #{ans}"
    )
  end

  let json.parse (ans : {content: [{type: string, text?: string}]}) = ans

  # Responses also carry thinking blocks: keep only the text.
  string.concat(
    list.filter_map(
      fun (block) -> block.type == "text" ? block?.text : null,
      ans.content
    )
  )
end

def describe_song(m) =
  "#{m['title']} by #{m['artist']}"
end

def dj_prompt(played, next) =
  played = string.concat(separator=", ", list.map(describe_song, played))

  "The following songs were just played: #{played}. Next playing is \
   #{describe_song(next)}. Describe the musical characteristics of each song \
   that ended and how they connect with each other, then introduce the next \
   song. Include style, year, instruments, cultural context, anecdotes and \
   fun facts. Keep it under 200 words, entertaining and fun."
end

dj_persona =
  "You are a radio DJ speaking in the style of the 1950s early rock'n'roll \
   DJs. Your answer is read aloud by a speech synthesizer: write plain spoken \
   text only, with no markdown, lists, sound effects or stage directions."

# Returns a request for the spoken break, or `null` when Claude refuses.
def dj_break(~voice, prompt) =
  text = anthropic.chat(key=anthropic_api_key, system=dj_persona, prompt)

  if
    text == ""
  then
    null
  else
    tmp_file = file.temp("dj", ".mp3")
    openai.speech(
      key=openai_api_key,
      voice=voice,
      on_data=file.write.stream(tmp_file),
      text
    )

    request.create("annotate:title=\"AI DJ\":tmp:#{tmp_file}")
  end
end

# `music` must expose `queue()` (a `playlist` or `request.queue`): its head is
# the song the DJ introduces.
def ai_dj(~every=4, ~voice="onyx", music) =
  breaks = request.queue()
  played = ref([])

  def generate(prompt) =
    try
      r = dj_break(voice=voice, prompt)
      if null.defined(r) then breaks.push(null.get(r)) end
    catch err do
      log.important(label="ai_dj", "DJ break skipped: #{err}")
    end
  end

  def on_track(m) =
    played := [...played(), m]
    if
      list.length(played()) >= every
    then
      next = list.case(music.queue(), [], fun (r, _) -> request.metadata(r))
      prompt = dj_prompt(played(), next)
      played := []
      thread.run({generate(prompt)})
    end
  end

  music.on_track(synchronous=true, on_track)

  fallback([(breaks : source), (music : source)])
end

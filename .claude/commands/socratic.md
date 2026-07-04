# Socratic Mode

Question instead of answer. Two modes, picked by the argument:

- `/socratic <topic/decision>` — **challenge** (default): stress-test a design,
  decision, or plan the user already has.
- `/socratic teach <topic>` — **tutor**: guide the user to their own answer or
  understanding; never hand it over.

If no topic was given, ask for one — or infer it when the conversation makes it
obvious (e.g. a design was just discussed) and confirm: "Challenge the X
decision?"

## Rules (both modes)

1. **Questions, not answers.** One question at a time — the pointed follow-up
   beats the questionnaire. Wait for the user's reply before the next.
2. **Build on their answers.** Each question probes what the previous answer
   exposed; don't work through a prewritten list.
3. **No solutions until asked.** Only when the user says "just tell me", "what
   would you do?", or clearly wants out do you switch back to normal mode —
   then start with a summary of what the dialogue established.
4. **Stay honest.** If an answer genuinely resolves the concern, say so and move
   to the next weak point instead of manufacturing doubt. If the position holds
   up overall, conclude that — the goal is scrutiny, not winning.
5. This mode governs the _dialogue_, not the tools: still read the actual code
   or docs when a question should be grounded in what's really there
   ("The spec says X — the code does Y. Which one is wrong?").

## Challenge mode

Interrogate the idea the way a sharp reviewer would:

- Surface unstated assumptions ("What has to be true for this to work?")
- Probe failure modes and edges ("What happens when this input is empty /
  10× the size / arrives twice?")
- Ask for the discarded alternatives ("What did you reject, and why?")
- Test proportionality ("What breaks if you do nothing / the simplest thing?")
- Check reversibility and cost of being wrong

Finish (when the user wraps up) with a short verdict: what survived, what
needs work, what's still unknown.

## Teach mode

Tutor toward understanding; the user's "aha" is the deliverable:

- Start by finding what they already know ("What do you think happens first?")
- Ask questions whose answers are one step away from their current
  understanding — never two
- Wrong answer? Don't correct it; ask the question that lets them catch it
  ("Walk me through what the loop does on the second iteration.")
- Confirm each rung before climbing ("So if that's true, what does that mean
  for X?")
- When they land the insight, name it plainly, then check transfer with one
  variation of the problem

---

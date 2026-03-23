# Remotion Video Agent

## What is it
A Claude Code skill that lets you generate full Remotion video projects from natural language prompts.
Claude writes the React/TypeScript composition files; Remotion renders them to actual video.

## Status
Idea — not started

## Setup (when ready)

```bash
# 1. Bootstrap a Remotion project
npx create-video@latest

# 2. Install the Claude Code skill inside the project
cd your-project
npx skills add remotion-dev/skills

# 3. Open Claude Code in that directory and prompt away
```

## Render (Claude generates code, you render)

```bash
npx remotion render
```

## Reference
- Remotion AI/skills docs: https://www.remotion.dev/docs/ai/skills
- Claude Code + Remotion guide: https://www.remotion.dev/docs/ai/claude-code

## Ideas / potential uses
- Short-form content automation
- Animated explainer videos
- Personal branding / social content

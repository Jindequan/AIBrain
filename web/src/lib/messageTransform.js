/**
 * Transform flat content array into structured Step-based format.
 *
 * Input:  [{type:'thinking'|'tool_use'|'text', step_index?, ...}]
 * Output: { steps: [{thinking, tools, collapsed}], content: textBlock|null }
 *
 * Step boundary detection:
 *   - When blocks have `step_index` (backend v2+): exact step boundary from the engine
 *   - When no `step_index` (old messages or SSE fallback): heuristic based on thinking blocks
 *     - thinking block → starts a new step
 *     - tool_use blocks after a thinking → same step
 *     - consecutive tool_use without thinking → same step
 *     - last text block = Content (L2), everything else = Trace (L1)
 *     - intermediate text blocks merge into preceding step's thinking
 */
export function contentToSteps(blocks) {
  if (!blocks || blocks.length === 0) return { steps: [], content: null }

  // Last text block = Content
  let contentBlock = null
  for (let i = blocks.length - 1; i >= 0; i--) {
    if (blocks[i].type === 'text') {
      contentBlock = blocks[i]
      break
    }
  }

  const hasStepIndex = blocks.some(b => b.step_index !== undefined)

  const steps = []
  let currentStep = null
  let orphanedText = ''

  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i]
    if (block === contentBlock) {
      // Prepend orphaned text (intermediate text before any step)
      if (orphanedText && contentBlock) {
        contentBlock = { ...contentBlock, text: orphanedText + '\n\n' + (contentBlock.text || '') }
        orphanedText = ''
      }
      if (currentStep) steps.push(currentStep)
      currentStep = null
      continue
    }

    if (block.type === 'thinking' || block.type === 'tool_use') {
      // Decide whether to start a new step
      const shouldStartNew =
        !currentStep ||
        (hasStepIndex && block.step_index !== currentStep._stepIndex) ||
        (!hasStepIndex && block.type === 'thinking')

      if (shouldStartNew) {
        // Flush orphaned text into the step being closed
        if (currentStep && orphanedText) {
          if (currentStep.thinking) {
            currentStep.thinking.text = (currentStep.thinking.text || '') + '\n\n' + orphanedText
          } else {
            currentStep.thinking = { type: 'thinking', text: orphanedText }
          }
          orphanedText = ''
        }
        if (currentStep) steps.push(currentStep)
        currentStep = {
          id: `step-${steps.length}`,
          thinking: null,
          tools: [],
          collapsed: true,
          _stepIndex: block.step_index,
        }
      }

      if (block.type === 'thinking') {
        currentStep.thinking = block
      } else {
        currentStep.tools.push(block)
      }
    } else if (block.type === 'text') {
      // Intermediate text — merge into current step's thinking
      if (currentStep) {
        if (currentStep.thinking) {
          currentStep.thinking.text = (currentStep.thinking.text || '') + '\n\n' + (block.text || '')
        } else {
          currentStep.thinking = { type: 'thinking', text: block.text || '' }
        }
      } else {
        // No active step yet — save to prepend to content block later
        orphanedText += (orphanedText ? '\n\n' : '') + (block.text || '')
      }
    }
  }

  // Flush remaining orphaned text into last step or content block
  if (currentStep && orphanedText) {
    if (currentStep.thinking) {
      currentStep.thinking.text = (currentStep.thinking.text || '') + '\n\n' + orphanedText
    } else {
      currentStep.thinking = { type: 'thinking', text: orphanedText }
    }
  } else if (!currentStep && orphanedText && contentBlock) {
    contentBlock = { ...contentBlock, text: orphanedText + '\n\n' + (contentBlock.text || '') }
  }
  if (currentStep) steps.push(currentStep)

  // Last step expanded, all prior steps collapsed
  if (steps.length > 0) {
    for (let i = 0; i < steps.length - 1; i++) steps[i].collapsed = true
    steps[steps.length - 1].collapsed = false
  }

  return { steps, content: contentBlock }
}

/**
 * Extract tool info for the capsule display.
 */
export function getToolIcon(name) {
  if (!name) return '🔧'
  if (/read|search|find|grep|lookup/i.test(name)) return '🔍'
  if (/write|create|edit|delete|remove|rename/i.test(name)) return '✏️'
  if (/shell|bash|exec|terminal|command|run/i.test(name)) return '💻'
  if (/web|browse|fetch|curl|http/i.test(name)) return '🌐'
  if (/list|dir|ls/i.test(name)) return '📁'
  if (/api|request|call/i.test(name)) return '🔗'
  if (/think|reason|plan|brain/i.test(name)) return '🧠'
  return '🔧'
}

export function getToolResourceInfo(tool) {
  if (!tool || !tool.input) return null
  const { input, name } = tool
  const filePath = input.file_path || input.path

  if (filePath) return filePath
  if (/shell|bash|exec/i.test(name)) {
    const cmd = input.command || input.cmd || ''
    return cmd.length > 60 ? cmd.slice(0, 57) + '...' : cmd
  }
  if (/web_search/i.test(name)) return input.query || null
  if (/api_request|fetch/i.test(name)) return input.url || null
  if (/browse/i.test(name)) return input.url || null
  return null
}

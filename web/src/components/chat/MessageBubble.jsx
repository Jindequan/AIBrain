import { useState, memo, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { Copy, Trash2, Pencil, RefreshCw, X, ShieldCheck, ArrowRight } from 'lucide-react'
import { ToolCallCard } from './ToolCallCard'
import { AggregatedToolCard } from './AggregatedToolCard'
import { ThinkingBlock } from './ThinkingBlock'
import { MarkdownContent } from './MarkdownContent'
import ContextMenu from '../desktop/ContextMenu'
import { cn } from '../../lib/utils'
import { useToast } from '../../hooks/useToast'
import { sessionsApi } from '../../api/sessions.api'
import { buildApiUrl } from '../../api/client'
import { TraceSteps } from './TraceSteps'
import { contentToSteps } from '../../lib/messageTransform'

function StreamingIndicator() {
  return (
    <span className="inline-flex items-center gap-1 ml-1.5">
      <span className="w-1.5 h-1.5 bg-accent/70 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
      <span className="w-1.5 h-1.5 bg-accent/70 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
      <span className="w-1.5 h-1.5 bg-accent/70 rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
    </span>
  )
}

function ContentBlocks({ blocks = [], streaming, onExpandImage }) {
  if (blocks.length === 0) {
    if (streaming) {
      return (
        <div className="flex items-center gap-1.5">
          <StreamingIndicator />
          <span className="text-xs text-text-muted">Thinking...</span>
        </div>
      )
    }
    return (
      <div className="text-xs text-text-muted italic">
        No content
      </div>
    )
  }

  const rendered = []
  let pendingGroup = []

  function flushGroup() {
    if (pendingGroup.length === 0) return
    if (pendingGroup.length === 1) {
      const call = pendingGroup[0]
      rendered.push({ type: 'tool_single', key: `tool-${call.id}-${rendered.length}`, call })
    } else {
      rendered.push({ type: 'tool_group', key: `toolgrp-${rendered.length}-${pendingGroup[0].id}`, calls: pendingGroup })
    }
    pendingGroup = []
  }

  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i]
    const nextBlock = blocks[i + 1]

    if (block.type === 'tool_use') {
      pendingGroup.push(block)
      if (!nextBlock || nextBlock.type !== 'tool_use' || nextBlock.name !== block.name) {
        flushGroup()
      }
    } else if (block.type === 'text') {
      flushGroup()
      rendered.push({ type: 'text_block', key: `text-${i}`, block })
    } else if (block.type === 'thinking') {
      flushGroup()
      rendered.push({ type: 'thinking_block', key: `think-${i}-${block.thinking_index || 0}`, block })
    } else if (block.type === 'image_url') {
      flushGroup()
      rendered.push({ type: 'image_block', key: `img-${i}`, block })
    }
  }
  flushGroup()

  return (
    <>
      {rendered.map((item, idx) => {
        if (item.type === 'text_block') {
          const isLastBlock = idx === rendered.length - 1
          return (
            <div key={item.key}>
              <MarkdownContent content={item.block.text} streaming={streaming && isLastBlock} />
              {streaming && isLastBlock && <StreamingIndicator />}
            </div>
          )
        }
        if (item.type === 'thinking_block') {
          return (
            <ThinkingBlock
              key={item.key}
              text={item.block.text}
              streaming={streaming && idx === rendered.length - 1}
            />
          )
        }
        if (item.type === 'image_block') {
          const url = item.block.image_url?.url || ''
          return <ImageBlock key={item.key} url={url} onExpand={onExpandImage} />
        }
        if (item.type === 'tool_group') {
          return (
            <AggregatedToolCard
              key={item.key}
              toolName={item.calls[0].name}
              calls={item.calls}
              streaming={streaming}
            />
          )
        }
        if (item.type === 'tool_single') {
          const call = item.call
          return (
            <ToolCallCard
              key={item.key}
              {...call}
              streaming={streaming && call.status === 'running'}
            />
          )
        }
        return null
      })}
    </>
  )
}

function AssistantMessageAggregator({ content, streaming }) {
  const { steps, content: finalBlock } = contentToSteps(content)
  const hasSteps = steps.length > 0
  const hasFinalText = finalBlock?.text?.trim()?.length > 0
  const thinkingSteps = steps.filter(step => step.thinking?.text?.trim()?.length > 0)

  if (!hasSteps && !hasFinalText) {
    if (streaming) {
      return (
        <div className="flex items-center gap-1.5">
          <StreamingIndicator />
          <span className="text-xs text-text-muted">Thinking...</span>
        </div>
      )
    }
    return null
  }

  return (
    <div className="space-y-2">
      {hasSteps && (
        <TraceSteps steps={steps} streaming={streaming} />
      )}
      {thinkingSteps.map((step, index) => (
        <ThinkingBlock
          key={step.id || `thinking-${index}`}
          text={step.thinking.text}
          streaming={streaming && !hasFinalText && index === thinkingSteps.length - 1}
        />
      ))}
      {hasFinalText && (
        <div className={cn(hasSteps && 'pt-1', '')}>
          <MarkdownContent content={finalBlock.text} />
          {streaming && !hasSteps && <StreamingIndicator />}
        </div>
      )}
      {streaming && hasSteps && !hasFinalText && (
        <div className="flex items-center gap-1.5 pl-1">
          <StreamingIndicator />
        </div>
      )}
    </div>
  )
}

import { formatMessageTime } from '../../lib/time'

function ImageBlock({ url, onExpand }) {
  const fullUrl = url?.startsWith('/') ? buildApiUrl(url) : url
  return (
    <div className="my-2">
      <img
        src={fullUrl}
        alt="Attached image"
        className="max-w-full max-h-64 object-contain rounded-xl border border-gray-200 dark:border-gray-700 cursor-pointer hover:opacity-90 transition-opacity"
        onClick={() => onExpand?.(fullUrl)}
      />
    </div>
  )
}

function ImageOverlay({ url, onClose }) {
  return (
    <div className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-8" onClick={onClose}>
      <button onClick={onClose}
        className="absolute top-4 right-4 p-2 rounded-full bg-white/20 text-white hover:bg-white/40 transition-colors" aria-label="Close">
        <X className="w-6 h-6" />
      </button>
      <img src={url} alt="Expanded image"
        className="max-w-full max-h-full object-contain rounded-2xl"
        onClick={(e) => e.stopPropagation()} />
    </div>
  )
}

function ActionBar({ items }) {
  if (items.length === 0) return null
  return (
    <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
      {items.map((item, i) => (
        item.type === 'separator' ? (
          <div key={i} className="w-px h-3.5 bg-gray-200 dark:bg-gray-700 mx-1" />
        ) : (
          <button key={i} onClick={item.onClick}
            className={cn(
              'p-1 rounded-md transition-colors',
              item.danger
                ? 'text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-950/30'
                : 'text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800'
            )}
            title={item.label} aria-label={item.label}>
            {item.icon}
          </button>
        )
      ))}
    </div>
  )
}

export const MessageBubble = memo(function MessageBubble({
  role, content = [], streaming, error, id, sessionId, created_at,
  onDelete, onEdit, onRegenerate, isLastAssistant, incomplete, system_type, approval
}) {
  const isUser = role === 'user'
  const isError = role === 'system' && error
  const isAssistant = role === 'assistant'
  const isApprovalRequired = role === 'system' && system_type === 'approval_required'
  const { addToast } = useToast()
  const [expandedImage, setExpandedImage] = useState(null)

  const handleCopy = useCallback(async () => {
    try {
      const text = content.filter(b => b.type === 'text').map(b => b.text || '').join('\n\n')
      await navigator.clipboard.writeText(text)
      addToast({ title: 'Copied', message: 'Message copied to clipboard', variant: 'success' })
    } catch (err) {
      addToast({ title: 'Copy Failed', message: err.message, variant: 'error' })
    }
  }, [content, addToast])

  const handleDelete = useCallback(async () => {
    if (!id || !sessionId || !onDelete) return
    try {
      await sessionsApi.deleteMessage(sessionId, id)
      addToast({ title: 'Deleted', message: 'Message deleted successfully', variant: 'success' })
      onDelete(id)
    } catch (err) {
      addToast({ title: 'Delete Failed', message: err.message || 'Failed to delete message', variant: 'error' })
    }
  }, [id, sessionId, onDelete, addToast])

  const canShowActions = id && sessionId && !streaming && !isError

  const contextMenuItems = []
  if (!streaming && !isError) {
    contextMenuItems.push({ label: 'Copy', icon: <Copy className="w-3.5 h-3.5" />, onClick: handleCopy })
  }
  if (isUser && onEdit) {
    contextMenuItems.push({ label: 'Edit', icon: <Pencil className="w-3.5 h-3.5" />, onClick: onEdit })
  }
  if (isAssistant && isLastAssistant && onRegenerate) {
    contextMenuItems.push({ label: 'Regenerate', icon: <RefreshCw className="w-3.5 h-3.5" />, onClick: onRegenerate })
  }
  if (canShowActions) {
    contextMenuItems.push({ separator: true })
    contextMenuItems.push({ label: 'Delete', icon: <Trash2 className="w-3.5 h-3.5" />, danger: true, onClick: handleDelete })
  }

  return (
    <ContextMenu items={contextMenuItems}>
      <div className={cn(
        'flex group py-1.5',
        isUser ? 'justify-end' : 'justify-start'
      )}>
        <div className={cn(
          'min-w-0 max-w-[90%]',
          isUser ? 'md:pl-16 lg:pl-24' : 'md:pr-16 lg:pr-24'
        )}>
          {/* Content */}
          <div className={cn(
            'min-w-0',
            isUser ? 'text-right' : 'text-left'
          )}>
            {isUser ? (
              <div className="px-4 py-2.5 rounded-2xl bg-accent/5 border border-accent/10">
                <p className="whitespace-pre-wrap leading-relaxed text-sm text-text-primary">
                  {content.find(b => b.type === 'text')?.text || ''}
                </p>
                {content.filter(b => b.type === 'image_url').map((block, i) => (
                  <ImageBlock key={`user-img-${i}`} url={block.image_url?.url || ''} onExpand={setExpandedImage} />
                ))}
                {!streaming && created_at && (
                  <p className="text-[11px] text-text-muted/50 mt-1">{formatMessageTime(created_at)}</p>
                )}
              </div>
            ) : isError ? (
              <p className="whitespace-pre-wrap leading-relaxed text-sm text-red-500">
                {content.find(b => b.type === 'text')?.text || 'An error occurred'}
              </p>
            ) : isAssistant ? (
              <div>
                <AssistantMessageAggregator content={content} streaming={streaming} />
                {incomplete && !streaming && (
                  <p className="text-xs text-amber-500 mt-1 font-medium">Response interrupted</p>
                )}
                {!streaming && created_at && (
                  <p className="text-[11px] text-text-muted/50 mt-1">{formatMessageTime(created_at)}</p>
                )}
              </div>
            ) : isApprovalRequired ? (
              <div className="rounded-lg border border-amber-400/30 bg-amber-500/10 px-3.5 py-3 text-sm text-text-primary">
                <div className="flex items-start gap-2.5">
                  <ShieldCheck className="w-4 h-4 mt-0.5 text-amber-600 shrink-0" />
                  <div className="min-w-0 flex-1 space-y-2">
                    <MarkdownContent content={content.find(b => b.type === 'text')?.text || 'Waiting for approval'} />
                    <div className="flex flex-wrap items-center gap-2">
                      <Link
                        to={approval?.approval_id ? `/approvals?interaction_id=${encodeURIComponent(approval.approval_id)}` : '/approvals'}
                        className="inline-flex items-center gap-1.5 rounded-md bg-amber-600 px-2.5 py-1.5 text-xs font-medium text-white hover:bg-amber-700 transition-colors"
                      >
                        Open approvals
                        <ArrowRight className="w-3.5 h-3.5" />
                      </Link>
                      {approval?.run_id && (
                        <span className="text-xs text-text-muted">Run {approval.run_id}</span>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <ContentBlocks blocks={content} streaming={streaming} onExpandImage={setExpandedImage} />
            )}

            {/* Hover actions */}
            {canShowActions && (
              <div className={cn('mt-1', isUser ? 'flex justify-end' : 'flex justify-start')}>
                <ActionBar items={[
                  ...(isUser && onEdit ? [{ label: 'Edit', icon: <Pencil className="w-3 h-3" />, onClick: onEdit }] : []),
                  ...(isAssistant && isLastAssistant && onRegenerate ? [{ label: 'Regenerate', icon: <RefreshCw className="w-3 h-3" />, onClick: onRegenerate }] : []),
                  { label: 'Copy', icon: <Copy className="w-3 h-3" />, onClick: handleCopy },
                  ...(id && sessionId ? [
                    { type: 'separator' },
                    { label: 'Delete', icon: <Trash2 className="w-3 h-3" />, danger: true, onClick: handleDelete }
                  ] : []),
                ]} />
              </div>
            )}
          </div>
        </div>
      </div>
      {expandedImage && <ImageOverlay url={expandedImage} onClose={() => setExpandedImage(null)} />}
    </ContextMenu>
  )
})

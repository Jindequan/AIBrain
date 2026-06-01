import { useEffect, useRef, useState, useCallback } from "react";
import { useParams, useNavigate, useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useVirtualizer } from "@tanstack/react-virtual";
import { Terminal, MessageSquare, ArrowRight, Clock, PanelRight } from "lucide-react";
import { SessionList } from "../components/chat/SessionList";
import { MessageBubble } from "../components/chat/MessageBubble";
import ChatContextPanel from "../components/chat/ChatContextPanel";
import { ChatInput } from "../components/chat/ChatInput";
import { ChatStatusBar } from "../components/chat/ChatStatusBar";
import { useWsStore } from "../store/wsStore";
import { useChatStore } from "../store/chatStore";
import { useInteractionStore } from "../store/interactionStore";
import { useToastStore } from "../store/toastStore";
import { useChatScroll } from "../hooks/useChatScroll";
import { useChatWebSocket } from "../hooks/useChatWebSocket";
import { buildApiUrl } from "../api/client";
import { sseQuery } from "../api/sse";
import { sessionsApi } from "../api/sessions.api";
import { normalizeRouteSessionId, resolveSendSessionId } from "../lib/chatFlow";
import { cn } from "../lib/utils.js"

function WelcomeScreen({ onSendExample, recentSessions, onOpenSession }) {
  const examples = [
    { text: "Organize my tasks for today by priority" },
    { text: "Summarize important news about companies I follow every morning" },
    { text: "Break down my content goals into a plan with ongoing tracking" },
    { text: "Analyze this workspace and generate a project status & risk report" },
  ]

  return (
    <div className="flex flex-col items-center justify-center h-full select-none">
      <div className="w-full max-w-xl px-6">
        {/* Logo */}
        <div className="flex flex-col items-center mb-12">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-accent to-accent-hover shadow-lg shadow-accent/20 flex items-center justify-center mb-4">
            <img src="/logo.png" alt="AIbrain" className="w-7 h-7" />
          </div>
          <h1 className="text-xl font-semibold text-text-primary tracking-tight">AIbrain</h1>
          <p className="text-sm text-text-muted mt-2">How can I help you today?</p>
        </div>

        {/* Suggestions */}
        <div className="space-y-2">
          {examples.map(({ text }, i) => (
            <button
              key={i}
              onClick={() => onSendExample(text)}
              className="group w-full text-left px-4 py-2.5 text-sm text-text-secondary hover:text-text-primary bg-white dark:bg-gray-800/40 hover:bg-gray-50 dark:hover:bg-gray-800/60 border border-gray-200 dark:border-gray-700/50 hover:border-gray-300 dark:hover:border-gray-600 rounded-xl transition-all cursor-pointer flex items-center justify-between gap-3"
            >
              <span className="flex-1 truncate">{text}</span>
              <ArrowRight className="w-3.5 h-3.5 text-text-muted shrink-0 opacity-0 group-hover:opacity-100 transition-all -translate-x-1 group-hover:translate-x-0" />
            </button>
          ))}
        </div>

        {/* Recent sessions */}
        {recentSessions.length > 0 && (
          <div className="mt-8 pt-6 border-t border-gray-100 dark:border-gray-800">
            <p className="text-xs text-text-muted font-medium mb-3 flex items-center gap-2">
              <Clock className="w-3.5 h-3.5" />
              Recent conversations
            </p>
            <div className="space-y-1">
              {recentSessions.slice(0, 5).map((s) => (
                <button
                  key={s.session_id || s.id}
                  onClick={() => onOpenSession(s.session_id || s.id)}
                  className="w-full text-left px-3 py-2 text-xs text-text-secondary hover:text-text-primary hover:bg-gray-100 dark:hover:bg-gray-800/50 rounded-lg transition-colors truncate flex items-center gap-2"
                >
                  <MessageSquare className="w-3 h-3 shrink-0 text-text-muted" />
                  <span className="truncate">{s.title || 'Untitled'}</span>
                </button>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

const LOADING_SKELETON_WIDTHS = [
  ['88%', '64%', '42%'],
  ['58%', '74%'],
  ['78%', '57%', '34%'],
  ['46%', '63%'],
]

function messageSyncSignature(messages = []) {
  return messages
    .map((m) => {
      const content = Array.isArray(m.content)
        ? m.content.map((b) => `${b.type || ''}:${b.text || b.id || b.tool_use_id || ''}`).join(',')
        : String(m.content || '')
      return `${m.id || ''}:${m.role || ''}:${content}`
    })
    .join('|')
}

export default function ChatPage() {
  const { session_id: urlSessionId } = useParams();
  const [input, setInput] = useState("");
  const [textareaExpanded, setTextareaExpanded] = useState(true);
  const [showPanel, setShowPanel] = useState(false);
  const [pendingImages, setPendingImages] = useState([]);
  const fileInputRef = useRef(null);
  const dragCounterRef = useRef(0);
  const sseControllerRef = useRef(null);
  const editTruncateIndexRef = useRef(null);
  const [isDragOver, setIsDragOver] = useState(false);
  const sessionSyncRef = useRef({ sessionId: null, signature: null });
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const qParamHandledRef = useRef(false);

  const [selectedGoalId, setSelectedGoalId] = useState(null);
  const [chatMode, setChatMode] = useState('chat');
  const [runMode, setRunMode] = useState('interactive');
  const [autonomyLevel, setAutonomyLevel] = useState(0);
  const [selectedModelSpec, setSelectedModelSpec] = useState(null);
  const lastModelSessionRef = useRef(null); // track which session's model we restored

  // Available models for the selector
  const { data: availableModels = [] } = useQuery({
    queryKey: ["available-models"],
    queryFn: async () => {
      const res = await fetch(buildApiUrl("/api/v1/models/all"))
      if (!res.ok) return []
      const data = await res.json()
      return data.models || []
    },
    staleTime: 30_000,
  });

  const { send, subscribe, connected: wsConnected } = useWsStore();
  const { addToast } = useToastStore();
  const {
    messages, streaming, status, activeSessionId, activeWorkspacePath, userStreaming,
    sessions: storedSessions, setActiveSession, setActiveWorkspacePath,
    addUserMessage, startStreaming, appendTextDelta, finishStreaming,
    setMessages, setStatus,
  } = useChatStore();

  const { scrollRef, bottomRef, userScrolledUp, handleScroll, scrollToBottom } =
    useChatScroll(messages, streaming, urlSessionId);
  const effectiveSessionId = normalizeRouteSessionId(urlSessionId);

  // Virtual scrolling
  // eslint-disable-next-line react-hooks/incompatible-library
  const virtualizer = useVirtualizer({
    count: messages.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: (index) => {
      const m = messages[index];
      if (!m) return 60;
      if (m.role === 'user') return 80;
      if (Array.isArray(m.content)) {
        const hasToolUse = m.content.some(b => b.type === 'tool_use');
        const textLen = m.content.reduce((acc, b) => acc + (b.text?.length || 0), 0);
        if (hasToolUse) return 160;
        if (textLen > 500) return 200;
        return 100;
      }
      return 60;
    },
    overscan: 10,
    getItemKey: (index) => `msg_${index}`,
  });

  // Load older messages on scroll to top
  const loadingOlderRef = useRef(false);
  const totalMessagesRef = useRef(0);
  const hasMoreRef = useRef(false);

  const handleScrollWithPagination = useCallback((e) => {
    handleScroll(e);
    const el = scrollRef.current;
    if (!el || loadingOlderRef.current || !hasMoreRef.current) return;
    if (el.scrollTop < 200) {
      loadingOlderRef.current = true;
      const before = messages.length > 0 ? totalMessagesRef.current - messages.length : undefined;
      if (!effectiveSessionId) {
        loadingOlderRef.current = false;
        return;
      }
      sessionsApi.getMessages(effectiveSessionId, { limit: 50, before })
        .then((res) => {
          if (res.messages?.length > 0) {
            useChatStore.getState().prependMessages(
              res.messages.map(m => ({
                ...m,
                content: Array.isArray(m.content) ? m.content : typeof m.content === 'string' ? [{ type: 'text', text: m.content }] : [],
                streaming: false,
              }))
            );
            totalMessagesRef.current = res.total;
            hasMoreRef.current = res.has_more;
          }
        })
        .finally(() => { loadingOlderRef.current = false; });
    }
  }, [effectiveSessionId, handleScroll, messages, scrollRef]);

  useChatWebSocket({ subscribe });

  const { data: sessionData, isLoading: isSessionLoading } = useQuery({
    queryKey: ["session", effectiveSessionId],
    queryFn: () => sessionsApi.get(effectiveSessionId),
    enabled: !!effectiveSessionId,
    refetchInterval: (data) => data?.status === "running" ? 5000 : false,
  });

  // Load messages via paginated endpoint (window of latest 50).
  // No refetchInterval during streaming — WebSocket/SSE events drive real-time updates.
  // Polling only for recovery: when session is running but user is not the driver
  // (e.g. reconnected after disconnect, or opened a running session).
  const { data: messagesData } = useQuery({
    queryKey: ["session-messages", effectiveSessionId],
    queryFn: () => sessionsApi.getMessages(effectiveSessionId, { limit: 50 }),
    enabled: !!effectiveSessionId,
  });

  // Recovery polling: fetch messages when session is running on backend
  // but the user is not actively streaming (reconnect / opened running session).
  useEffect(() => {
    if (!effectiveSessionId) return;
    const interval = setInterval(() => {
      const store = useChatStore.getState();
      if (!store.userStreaming && sessionData?.status === "running") {
        queryClient.invalidateQueries({ queryKey: ["session-messages", effectiveSessionId] });
        queryClient.invalidateQueries({ queryKey: ["session", effectiveSessionId] });
      }
    }, 3000);
    return () => clearInterval(interval);
  }, [effectiveSessionId, sessionData?.status, queryClient]);

  useEffect(() => {
    if (!sessionData) return;

    const isNewSession = sessionSyncRef.current.sessionId !== effectiveSessionId;
    if (isNewSession) {
      loadingOlderRef.current = false;
      hasMoreRef.current = false;
    }

    const serverMessages = messagesData?.messages || [];
    const totalCount = messagesData?.total ?? sessionData.message_count ?? 0;
    const hasMore = messagesData?.has_more ?? false;

    totalMessagesRef.current = totalCount;
    hasMoreRef.current = hasMore;

    // Check streaming from the store directly, NOT from the deps array.
    // If streaming is a dep, this effect fires when streaming ends and
    // overwrites the streaming message with stale server data (fetched
    // Skip sync during user-initiated streaming (SSE/WebSocket drives updates).
    // During recovery (session running on backend but no active user stream),
    // allow sync so polled messages update the UI.
    const store = useChatStore.getState();
    if (store.streaming && store.userStreaming) return;

    // Never overwrite local messages while an approval interaction is pending.
    const pendingApproval = useInteractionStore.getState().queue.some(
      (i) => i.status === 'pending' && i.type === 'approval'
    );
    if (pendingApproval) return;

    const signature = messageSyncSignature(serverMessages);

    if (isNewSession || sessionSyncRef.current.signature !== signature) {
      // Don't overwrite error messages with server data. Errors must remain
      // visible until the user sends a new message or switches sessions.
      const currentMessages = useChatStore.getState().messages;
      const hasError = currentMessages.length > 0 && currentMessages[currentMessages.length - 1]?.error;
      if (hasError) return;

      // Safety: never clear messages if we have local content and server returned empty.
      // This prevents a refetch race from blanking the chat after streaming completes.
      if (serverMessages.length === 0 && currentMessages.length > 0) return;

      sessionSyncRef.current = { sessionId: effectiveSessionId, signature };

      const normalized = serverMessages.map(m => ({
        ...m,
        content: Array.isArray(m.content) ? m.content : typeof m.content === 'string' ? [{ type: 'text', text: m.content }] : [],
        streaming: false,
      }));
      setMessages(normalized);
    }
  }, [effectiveSessionId, sessionData, messagesData, setMessages]);

  // Restore session-scoped config from backend metadata on session switch / refresh
  useEffect(() => {
    if (effectiveSessionId && effectiveSessionId !== lastModelSessionRef.current) {
      lastModelSessionRef.current = effectiveSessionId;
      setSelectedModelSpec(sessionData?.requested_model || null);
      if (sessionData?.metadata?.chat_mode) setChatMode(sessionData.metadata.chat_mode);
      if (sessionData?.metadata?.run_mode) setRunMode(sessionData.metadata.run_mode);
    }
  }, [sessionData?.requested_model, sessionData?.metadata?.chat_mode, sessionData?.metadata?.run_mode, effectiveSessionId]);

  // Recovery: when the session is running on the backend but we're not in a
  // user-initiated stream, enter/exit recovery mode to poll for new messages.
  useEffect(() => {
    if (!sessionData || !effectiveSessionId) return;
    const store = useChatStore.getState();
    const isRunning = sessionData.status === "running";

    if (isRunning && !store.userStreaming && !store.streaming) {
      useChatStore.setState({ streaming: true });
      // Mark last assistant as streaming so the UI shows the indicator
      const msgs = store.messages;
      if (msgs.length > 0) {
        const last = msgs[msgs.length - 1];
        if (last.role === "assistant" && !last.streaming) {
          useChatStore.setState({
            messages: [...msgs.slice(0, -1), { ...last, streaming: true }],
          });
        }
      }
    } else if (!isRunning && store.streaming && !store.userStreaming) {
      finishStreaming();
    }
  }, [sessionData?.status, effectiveSessionId, finishStreaming]);

  const conversationStarted = messages.length > 0;

  const handleWorkspacePathChange = useCallback((path) => {
    setActiveWorkspacePath(path);
  }, [setActiveWorkspacePath]);

  const handleImageSelect = useCallback((e) => {
    const files = Array.from(e.target.files || []);
    const valid = files.filter(f => f.type.startsWith('image/'));
    const newImages = valid.map(file => ({ file, preview: URL.createObjectURL(file) }));
    setPendingImages(prev => [...prev, ...newImages]);
    if (e.target) e.target.value = '';
  }, []);

  const handleRemoveImage = useCallback((index) => {
    setPendingImages(prev => {
      const img = prev[index];
      if (img?.preview) URL.revokeObjectURL(img.preview);
      return prev.filter((_, i) => i !== index);
    });
  }, []);

  const handlePaste = useCallback((e) => {
    const items = e.clipboardData?.items;
    if (!items) return;
    const imageFiles = [];
    for (const item of items) {
      if (item.type.startsWith('image/')) {
        const file = item.getAsFile();
        if (file) imageFiles.push(file);
      }
    }
    if (imageFiles.length > 0) {
      e.preventDefault();
      const newImages = imageFiles.map(file => ({ file, preview: URL.createObjectURL(file) }));
      setPendingImages(prev => [...prev, ...newImages]);
    }
  }, []);

  const handleDragEnter = useCallback((e) => { e.preventDefault(); e.stopPropagation(); dragCounterRef.current += 1; setIsDragOver(true); }, []);
  const handleDragLeave = useCallback((e) => { e.preventDefault(); e.stopPropagation(); dragCounterRef.current -= 1; if (dragCounterRef.current <= 0) { dragCounterRef.current = 0; setIsDragOver(false); } }, []);
  const handleDragOver = useCallback((e) => { e.preventDefault(); e.stopPropagation(); }, []);
  const handleDrop = useCallback((e) => { e.preventDefault(); e.stopPropagation(); setIsDragOver(false); dragCounterRef.current = 0; const files = Array.from(e.dataTransfer?.files || []); const valid = files.filter(f => f.type.startsWith('image/')); if (valid.length > 0) { const newImages = valid.map(file => ({ file, preview: URL.createObjectURL(file) })); setPendingImages(prev => [...prev, ...newImages]); } }, []);

  async function uploadImage(file) {
    const formData = new FormData();
    formData.append('file', file);
    const res = await fetch(buildApiUrl('/api/v1/files/upload'), { method: 'POST', body: formData });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `Upload failed: ${res.status}`);
    }
    return res.json();
  }

  useEffect(() => {
    return () => { pendingImages.forEach(img => { if (img.preview) URL.revokeObjectURL(img.preview); }); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    return () => {
      sseControllerRef.current?.abort();
      sseControllerRef.current = null;
      // Clear userStreaming on unmount so that re-mounting enters recovery
      // mode if the session is still running on the backend.
      useChatStore.setState({ userStreaming: false });
    };
  }, []);

  useEffect(() => {
    if (effectiveSessionId !== activeSessionId) {
      setActiveSession(effectiveSessionId);
      if (!effectiveSessionId) sessionSyncRef.current = { sessionId: null, signature: null };
    }
  }, [effectiveSessionId, activeSessionId, setActiveSession]);

  useEffect(() => {
    const q = searchParams.get('q');
    if (q && !qParamHandledRef.current) {
      qParamHandledRef.current = true;
      setInput(q);
      navigate('/chat', { replace: true });
    }
  }, [searchParams, navigate]);

  // Persist chat mode / run mode via backend session metadata
  useEffect(() => { /* chat_mode persisted via session query param */ }, [chatMode]);
  useEffect(() => { /* run_mode persisted via session query param */ }, [runMode]);
  // Persist only when user manually picks a model (not when restored from session)
  const handleUserSelectModel = useCallback((modelSpec) => {
    setSelectedModelSpec(modelSpec);
  }, []);

  async function handleSend() {
    const hasText = input.trim().length > 0;
    const hasImages = pendingImages.length > 0;
    if (!hasText && !hasImages) return;
    if (streaming) return;

    let sessionId = resolveSendSessionId(urlSessionId, activeSessionId);
    if (!sessionId) {
      try {
        const body = activeWorkspacePath || selectedModelSpec ? { workspace_path: activeWorkspacePath, model: selectedModelSpec || undefined } : undefined;
        const res = await sessionsApi.create(body);
        sessionId = res.session_id;
        setActiveSession(sessionId);
        navigate(`/sessions/${sessionId}`, { replace: true });
        queryClient.invalidateQueries({ queryKey: ['sessions'] });
      } catch {
        addToast({ title: "Failed to create session", message: "Could not create session", variant: "error" });
        return;
      }
    }

    const uploadErrors = [];
    const contentBlocks = [];
    if (hasText) contentBlocks.push({ type: 'text', text: input.trim() });

    // Upload all images in parallel
    const uploadResults = await Promise.allSettled(
      pendingImages.map(img => {
        if (img.uploaded) return Promise.resolve({ type: 'image_url', image_url: { url: img.preview } });
        return uploadImage(img.file).then(result => ({ type: 'image_url', image_url: { url: result.url } }));
      })
    );
    for (const r of uploadResults) {
      if (r.status === 'fulfilled') {
        contentBlocks.push(r.value);
      } else {
        uploadErrors.push(r.reason?.message || 'Upload failed');
      }
    }
    if (uploadErrors.length === pendingImages.length && !hasText) {
      addToast({ title: "Upload failed", message: "All image uploads failed — nothing to send", variant: "error" });
      return;
    }
    if (uploadErrors.length > 0) addToast({ title: "Partial upload failed", message: uploadErrors.join(', '), variant: "warning" });
    if (contentBlocks.length === 0) return;

    if (editTruncateIndexRef.current != null && sessionId) {
      try {
        await sessionsApi.truncateMessages(sessionId, editTruncateIndexRef.current);
        queryClient.invalidateQueries({ queryKey: ['session', sessionId] });
        queryClient.invalidateQueries({ queryKey: ['session-messages', sessionId] });
      } catch (err) {
        addToast({ title: "Edit failed", message: err.message || "Could not update session history", variant: "error" });
        return;
      }
    }
    editTruncateIndexRef.current = null;

    addUserMessage(contentBlocks);
    startStreaming();
    setStatus({ text: "Working on it...", type: "info" });

    const taskConfig = {
      session_id: sessionId,
      workspace_path: activeWorkspacePath || undefined,
      goal_id: selectedGoalId || undefined,
      run_mode: runMode || 'interactive',
      autonomy_level: autonomyLevel || 0,
      model: selectedModelSpec || undefined,
      chat_mode: chatMode || 'chat',
      metadata: {
        entrypoint: 'chat',
        assistant_mode: chatMode || 'interactive',
      },
    };

    const query = hasImages
      ? { ...taskConfig, messages: [{ role: 'user', content: contentBlocks }] }
      : { ...taskConfig, message: input.trim() };

    const sentViaWs = wsConnected && send(query);
    if (!sentViaWs) {
      setStatus({ text: "WebSocket disconnected, falling back to SSE...", type: "info" });
      sseControllerRef.current = sseQuery(query, {
        onTextDelta: (text) => appendTextDelta(text),
        onToolResult: (data) => { if (data.tool_use_id) { const { addToolUse, setToolResult } = useChatStore.getState(); addToolUse(data.tool_name || "tool", data.tool_use_id, data.input || null); setToolResult(data.tool_use_id, data.output, data.status); } },
        onComplete: (response) => {
          sseControllerRef.current = null;
          useChatStore.getState().appendAssistantTextIfEmpty(response || '');
          finishStreaming();
          // Don't invalidate the active session — messages already up-to-date from streaming.
          queryClient.invalidateQueries({ queryKey: ['sessions'] });
        },
        onSuspended: (approval) => {
          sseControllerRef.current = null;
          const chat = useChatStore.getState();
          chat.addApprovalRequiredMessage(approval);
          addToast({ title: "Approval required", message: approval?.reason || "Open approvals to continue", variant: "warning" });
          // Don't invalidate the active session — local approval message must not be overwritten.
          queryClient.invalidateQueries({ queryKey: ['sessions'] });
          queryClient.invalidateQueries({ queryKey: ['interactions'] });
        },
        onError: (err) => { sseControllerRef.current = null; addToast({ title: "Query failed", message: err, variant: "error" }); finishStreaming(err); },
        onWarning: (warning) => { addToast({ title: "Warning", message: warning, variant: "warning" }); },
      });
    }

    setInput("");
    pendingImages.forEach(img => { if (img.preview) URL.revokeObjectURL(img.preview); });
    setPendingImages([]);
  }

  const handleMessageDelete = async (messageId) => {
    setMessages((prev) => prev.filter((m) => m.id !== messageId));
    try {
      await sessionsApi.deleteMessage(effectiveSessionId, messageId);
    } catch {
      // Revert on failure
      addToast({ title: "Delete failed", message: "Could not delete message from server", variant: "error" });
      queryClient.invalidateQueries({ queryKey: ["session", effectiveSessionId] });
    }
  };

  const handleEdit = useCallback((msgIndex) => {
    const msgs = useChatStore.getState().messages;
    // CRITICAL: Must validate msgIndex BEFORE using it to access array
    if (typeof msgIndex !== 'number' || msgIndex < 0 || msgIndex >= msgs.length) {
      console.error('Invalid msgIndex for handleEdit:', msgIndex, 'Expected number, got:', typeof msgIndex);
      return;
    }
    const msg = msgs[msgIndex];
    if (!msg) return;

    const text = msg.content?.find((b) => b.type === 'text')?.text || '';
    const images = msg.content?.filter((b) => b.type === 'image_url') || [];
    const loadedOffset = Math.max(0, (totalMessagesRef.current || msgs.length) - msgs.length);
    editTruncateIndexRef.current = loadedOffset + msgIndex;
    setMessages(() => msgs.slice(0, msgIndex));
    setInput(text);
    setPendingImages(images.map((b) => ({ file: null, preview: b.image_url?.url || '', uploaded: true })));
  }, [setMessages]);

  const handleRegenerate = useCallback((msgIndex) => {
    const msgs = useChatStore.getState().messages;
    if (typeof msgIndex !== 'number' || msgIndex < 0 || msgIndex >= msgs.length) {
      console.error('Invalid msgIndex:', msgIndex);
      return;
    }
    const userMsg = msgs.slice(0, msgIndex).findLast((m) => m.role === 'user');
    if (!userMsg) return;
    const text = userMsg.content?.find((b) => b.type === 'text')?.text || '';
    const images = userMsg.content?.filter((b) => b.type === 'image_url') || [];
    const userMsgIndex = msgs.lastIndexOf(userMsg);
    const loadedOffset = Math.max(0, (totalMessagesRef.current || msgs.length) - msgs.length);
    editTruncateIndexRef.current = loadedOffset + userMsgIndex;
    setMessages(() => msgs.slice(0, userMsgIndex));
    setInput(text);
    setPendingImages(images.map((b) => ({ file: null, preview: b.image_url?.url || '', uploaded: true })));
  }, [setMessages]);

  const handleSendExample = useCallback((text) => { setInput(text); }, []);
  const handleStop = useCallback(() => {
    const sessionId = resolveSendSessionId(urlSessionId, activeSessionId);
    sseControllerRef.current?.abort();
    sseControllerRef.current = null;
    if (sessionId) {
      sessionsApi.stop(sessionId)
        .then(() => {
          queryClient.invalidateQueries({ queryKey: ['session', sessionId] })
          queryClient.invalidateQueries({ queryKey: ['sessions'] })
        })
        .catch(() => {})
    }
    useChatStore.getState().interruptStreaming();
  }, [activeSessionId, queryClient, urlSessionId]);

  useEffect(() => {
    const { scrollTargetSessionId, scrollTargetMessageIndex, clearScrollTarget } = useChatStore.getState();
    if (scrollTargetMessageIndex == null) return;
    if (scrollTargetSessionId && scrollTargetSessionId !== effectiveSessionId) return;
    const el = scrollRef.current?.querySelector(`[data-message-idx="${scrollTargetMessageIndex}"]`);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      el.classList.add('ring-2', 'ring-accent', 'rounded-2xl');
      setTimeout(() => el.classList.remove('ring-2', 'ring-accent', 'rounded-2xl'), 2000);
    }
    clearScrollTarget();
  }, [effectiveSessionId, messages, scrollRef]);

  return (
    <div className="flex h-full bg-white dark:bg-gray-950">
      <SessionList />
      <div className="flex flex-col flex-1 overflow-hidden">

        <input ref={fileInputRef} type="file" accept="image/*" multiple className="hidden" onChange={handleImageSelect} />

        {isDragOver && (
          <div className="absolute inset-0 z-40 bg-accent/10 backdrop-blur-sm flex items-center justify-center border-2 border-dashed border-accent/40 mx-4 my-4 rounded-3xl">
            <div className="flex flex-col items-center gap-2">
              <div className="p-3 rounded-2xl bg-accent/20">
                <Terminal className="w-6 h-6 text-accent" />
              </div>
              <p className="text-sm font-medium text-accent">Drop images here</p>
            </div>
          </div>
        )}

        <div
          ref={scrollRef}
          onScroll={handleScrollWithPagination}
          onPaste={handlePaste}
          onDragEnter={handleDragEnter}
          onDragLeave={handleDragLeave}
          onDragOver={handleDragOver}
          onDrop={handleDrop}
          className="flex-1 overflow-y-auto scroll-smooth"
        >
          {isSessionLoading && messages.length === 0 && (
            <div className="px-6 py-8 space-y-5 mx-auto max-w-4xl">
              {Array.from({ length: 4 }).map((_, i) => (
                <div key={i} className={cn("flex gap-3", i % 2 === 0 ? "" : "flex-row-reverse")}>
                  <div className={cn(
                    "rounded-2xl p-4",
                    i % 2 === 0 ? "bg-white dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700/50" : "bg-gray-50 dark:bg-gray-800",
                    i % 2 === 0 ? "w-3/5" : "w-2/5"
                  )}>
                    <div className="space-y-2.5">
                      <div className="h-3 rounded-full bg-gray-200 dark:bg-gray-700 animate-pulse" style={{ width: LOADING_SKELETON_WIDTHS[i][0] }} />
                      <div className="h-3 rounded-full bg-gray-200 dark:bg-gray-700 animate-pulse" style={{ width: LOADING_SKELETON_WIDTHS[i][1] }} />
                      {i % 2 === 0 && <div className="h-3 rounded-full bg-gray-200 dark:bg-gray-700 animate-pulse" style={{ width: LOADING_SKELETON_WIDTHS[i][2] }} />}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
          {!isSessionLoading && messages.length === 0 && (
            <WelcomeScreen
              onSendExample={handleSendExample}
              recentSessions={(storedSessions || []).slice(0, 6)}
              onOpenSession={(id) => { setActiveSession(id); navigate(`/sessions/${id}`); }}
            />
          )}
          {messages.length > 0 && (
            <div className="px-4 py-6 mx-auto w-full max-w-4xl" style={{ height: virtualizer.getTotalSize(), position: 'relative' }}>
              {virtualizer.getVirtualItems().map((virtualRow) => {
                const m = messages[virtualRow.index];
                if (!m) return null;
                const i = virtualRow.index;
                const isAssistant = m.role === 'assistant';
                const isLastAssistant = isAssistant && i === messages.length - 1;
                return (
                  <div
                    key={virtualRow.key}
                    ref={virtualizer.measureElement}
                    data-index={virtualRow.index}
                    data-message-idx={i}
                    style={{
                      position: 'absolute',
                      top: 0,
                      left: 0,
                      width: '100%',
                      transform: `translateY(${virtualRow.start}px)`,
                    }}
                  >
                    <div className="max-w-4xl mx-auto">
                      <MessageBubble
                        {...m}
                        sessionId={effectiveSessionId}
                        onDelete={handleMessageDelete}
                        onEdit={m.role === 'user' ? () => handleEdit(i) : undefined}
                        onRegenerate={isLastAssistant ? () => handleRegenerate(i) : undefined}
                        isLastAssistant={isLastAssistant}
                      />
                    </div>
                  </div>
                );
              })}
              <div ref={bottomRef} />
            </div>
          )}
          {userScrolledUp && streaming && (
            <div className="sticky bottom-4 flex justify-center">
              <button onClick={() => scrollToBottom(true)}
                className="px-4 py-1.5 text-xs font-medium rounded-full bg-accent text-white shadow-lg hover:bg-accent/90 hover:-translate-y-0.5 transition-all animate-bounce">
                ↓ New content
              </button>
            </div>
          )}
        </div>

        <ChatStatusBar status={status} />

        <div className="shrink-0">
          <ChatInput
            input={input} setInput={setInput} onSend={handleSend} onStop={handleStop} streaming={streaming}
            textareaExpanded={textareaExpanded} onToggleExpand={() => setTextareaExpanded((v) => !v)}
            pendingImages={pendingImages} onRemoveImage={handleRemoveImage}
            onAttachImage={() => fileInputRef.current?.click()}
            workspacePath={activeWorkspacePath}
            onWorkspacePathChange={handleWorkspacePathChange}
            workspaceLocked={conversationStarted}
            selectedGoalId={selectedGoalId}
            onSelectGoal={setSelectedGoalId}
            mode={chatMode}
            onModeChange={(nextMode, nextRunMode) => {
              setChatMode(nextMode)
              setRunMode(nextRunMode || 'interactive')
            }}
            autonomyLevel={autonomyLevel}
            onAutonomyLevelChange={setAutonomyLevel}
            availableModels={availableModels}
            selectedModelSpec={selectedModelSpec}
            onSelectModel={handleUserSelectModel}
          />
        </div>

        {/* Floating context panel button */}
        <button
          onClick={() => setShowPanel((v) => !v)}
          className={cn(
            "fixed bottom-6 right-6 z-30 flex items-center gap-2 px-4 py-2.5 rounded-full shadow-lg transition-all duration-200",
            "bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700",
            "hover:shadow-xl hover:scale-105",
            "text-sm font-medium text-text-secondary hover:text-text-primary"
          )}
          title="Open context panel"
        >
          <PanelRight className="w-4 h-4" />
          <span className="hidden sm:inline">Context</span>
        </button>
      </div>
      {showPanel && <ChatContextPanel sessionId={effectiveSessionId || activeSessionId} workspacePath={activeWorkspacePath} onClose={() => setShowPanel(false)} />}
    </div>
  );
}

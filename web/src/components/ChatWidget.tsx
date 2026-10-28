import { useEffect, useRef, useState } from 'react';
import { Button, Empty, Input, Popconfirm, Space, Spin, Tag, Typography, theme } from 'antd';
import { BookOutlined, CloseOutlined, DeleteOutlined, MessageOutlined, RobotOutlined, SendOutlined, UserOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import Markdown from 'react-markdown';
import { chatApi, type ChatMessage } from '../api/chat';
import { errorMessage } from '../api/client';
import { useAuth } from '../auth/AuthContext';

const SUGGESTIONS = [
  'How am I doing in my marks?',
  'Which skills should I improve for placements?',
  'Which placement drives am I eligible for?',
  'Give me interview questions to practice',
];

/** Floating AI assistant (bottom-right). Answers come from the college's own data through the backend. */
export default function ChatWidget() {
  const { can } = useAuth();
  const { token } = theme.useToken();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [text, setText] = useState('');
  // The question being answered, shown right away because the saved history only updates once the answer is back.
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const bottom = useRef<HTMLDivElement>(null);

  const allowed = can('chat.use');
  const { data: history = [], isLoading } = useQuery({ queryKey: ['chat', 'history'], queryFn: () => chatApi.history(), enabled: allowed && open });

  const ask = useMutation({
    mutationFn: chatApi.ask,
    onMutate: (q) => {
      setPending(q);
      setError(null);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['chat', 'history'] }),
    onError: (e) => setError(errorMessage(e)),
    onSettled: () => setPending(null),
  });
  const clear = useMutation({
    mutationFn: chatApi.clear,
    onSuccess: () => qc.setQueryData(['chat', 'history'], []),
  });

  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [history.length, pending, open]);

  if (!allowed) return null;

  const send = (q: string) => {
    const msg = q.trim();
    if (!msg || ask.isPending) return;
    setText('');
    ask.mutate(msg);
  };

  const bubble = (m: Pick<ChatMessage, 'role' | 'content'> & { sources?: ChatMessage['sources'] }, key: string | number) => {
    const mine = m.role === 'user';
    return (
      <div key={key} style={{ display: 'flex', gap: 8, flexDirection: mine ? 'row-reverse' : 'row', marginBottom: 12 }}>
        <div style={{ width: 28, height: 28, borderRadius: '50%', flex: 'none', display: 'grid', placeItems: 'center',
          background: mine ? token.colorFillSecondary : token.colorPrimary, color: mine ? token.colorText : '#fff' }}>
          {mine ? <UserOutlined /> : <RobotOutlined />}
        </div>
        <div style={{ maxWidth: '82%', padding: '8px 12px', borderRadius: 12, fontSize: 13.5, lineHeight: 1.5, wordBreak: 'break-word',
          background: mine ? token.colorPrimary : token.colorFillQuaternary, color: mine ? '#fff' : token.colorText }}>
          {mine ? m.content : <div className="chat-md"><Markdown>{m.content}</Markdown></div>}
          {!mine && m.sources && m.sources.length > 0 && (
            <div style={{ marginTop: 8, paddingTop: 6, borderTop: `1px solid ${token.colorBorderSecondary}`, fontSize: 12, color: token.colorTextSecondary }}>
              <BookOutlined /> Sources:{' '}
              {m.sources.map((s) => (
                <Tag key={s.document_id} style={{ marginInlineEnd: 4, whiteSpace: 'normal' }}>{s.title}</Tag>
              ))}
            </div>
          )}
        </div>
      </div>
    );
  };

  return (
    <>
      <style>{`.chat-md p{margin:0 0 6px}.chat-md p:last-child{margin:0}.chat-md ul,.chat-md ol{margin:0 0 6px;padding-left:18px}`}</style>
      {open ? (
        <div role="dialog" aria-label="AI assistant"
          style={{ position: 'fixed', right: 20, bottom: 20, zIndex: 1000, width: 'min(380px, calc(100vw - 24px))', height: 'min(560px, calc(100vh - 40px))',
            display: 'flex', flexDirection: 'column', background: token.colorBgElevated, border: `1px solid ${token.colorBorderSecondary}`,
            borderRadius: 14, boxShadow: token.boxShadowSecondary, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 14px', background: token.colorPrimary, color: '#fff' }}>
            <RobotOutlined />
            <Typography.Text strong style={{ color: '#fff', flex: 1 }}>EduSkill Assistant</Typography.Text>
            <Popconfirm title="Clear this conversation?" okText="Clear" onConfirm={() => clear.mutate()} disabled={history.length === 0}>
              <Button type="text" size="small" icon={<DeleteOutlined />} style={{ color: '#fff' }} disabled={history.length === 0} aria-label="Clear conversation" />
            </Popconfirm>
            <Button type="text" size="small" icon={<CloseOutlined />} style={{ color: '#fff' }} onClick={() => setOpen(false)} aria-label="Close" />
          </div>

          <div style={{ flex: 1, overflowY: 'auto', padding: 14 }}>
            {isLoading ? (
              <Spin style={{ display: 'block', marginTop: 40 }} />
            ) : history.length === 0 && !pending ? (
              <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="Ask about your marks, skills, placements or interview prep">
                <Space orientation="vertical" size={6}>
                  {SUGGESTIONS.map((s) => (
                    <Tag key={s} color="processing" style={{ cursor: 'pointer', whiteSpace: 'normal', margin: 0 }} onClick={() => send(s)}>{s}</Tag>
                  ))}
                </Space>
              </Empty>
            ) : (
              history.map((m) => bubble(m, m.id))
            )}
            {pending && bubble({ role: 'user', content: pending }, 'pending')}
            {ask.isPending && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: token.colorTextSecondary, fontSize: 13 }}>
                <Spin size="small" /> Thinking… this can take a little while
              </div>
            )}
            {error && <Typography.Text type="danger" style={{ fontSize: 13 }}>{error}</Typography.Text>}
            <div ref={bottom} />
          </div>

          <div style={{ display: 'flex', gap: 8, padding: 10, borderTop: `1px solid ${token.colorBorderSecondary}` }}>
            <Input.TextArea value={text} onChange={(e) => setText(e.target.value)} placeholder="Ask a question…" maxLength={1000}
              autoSize={{ minRows: 1, maxRows: 4 }} disabled={ask.isPending}
              onPressEnter={(e) => {
                if (!e.shiftKey) {
                  e.preventDefault();
                  send(text);
                }
              }} />
            <Button type="primary" icon={<SendOutlined />} onClick={() => send(text)} loading={ask.isPending} disabled={!text.trim()} aria-label="Send" />
          </div>
        </div>
      ) : (
        <Button type="primary" shape="circle" size="large" icon={<MessageOutlined />} aria-label="Open AI assistant" onClick={() => setOpen(true)}
          style={{ position: 'fixed', right: 24, bottom: 24, zIndex: 1000, width: 52, height: 52, boxShadow: token.boxShadowSecondary }} />
      )}
    </>
  );
}

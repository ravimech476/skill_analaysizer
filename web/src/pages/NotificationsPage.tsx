import { useState } from 'react';
import { Alert, Button, Card, Empty, Form, Input, List, Modal, Radio, Segmented, Select, Space, Switch, Table, Tabs, Typography, message } from 'antd';
import { CheckOutlined, DeleteOutlined, SendOutlined } from '@ant-design/icons';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { useNavigate } from 'react-router-dom';
import { errorMessage } from '../api/client';
import { noticeLink, notificationsApi, type Notice, type SendInput } from '../api/notifications';
import { rolesApi } from '../api/endpoints';
import { studentsApi } from '../api/phase2';
import { useClasses, useDepartments } from '../api/lookups';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { TypeTag } from '../components/NotificationBell';
import type { UploadedFile } from '../api/files';
import { FileAnchor, UploadButton } from '../components/Files';

function InboxView() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const staff = ['admin', 'staff'].includes(audienceOf(user?.roles ?? []));
  const [filter, setFilter] = useState<string>('all');
  const [page, setPage] = useState(1);
  const params = { page, page_size: 20, unread_only: filter === 'unread' || undefined, type: ['placement', 'marks', 'skill', 'general'].includes(filter) ? filter : undefined };
  const { data, isFetching } = useQuery({ queryKey: ['notifications', 'inbox', params], queryFn: () => notificationsApi.inbox(params), placeholderData: keepPreviousData });

  const refresh = () => qc.invalidateQueries({ queryKey: ['notifications'] });
  const read = useMutation({ mutationFn: (id: number) => notificationsApi.markRead(id), onSuccess: refresh });
  const hide = useMutation({ mutationFn: (id: number) => notificationsApi.hide(id), onSuccess: refresh, onError: (e) => message.error(errorMessage(e)) });
  const readAll = useMutation({ mutationFn: notificationsApi.readAll, onSuccess: refresh });

  const open = (n: Notice) => {
    if (!n.is_read) read.mutate(n.id);
    const link = noticeLink(n, staff);
    if (link) navigate(link);
  };

  return (
    <>
      <Space wrap style={{ marginBottom: 16, width: '100%', justifyContent: 'space-between' }}>
        <Segmented
          value={filter}
          onChange={(v) => {
            setFilter(v as string);
            setPage(1);
          }}
          options={[
            { value: 'all', label: 'All' },
            { value: 'unread', label: `Unread${data?.unread ? ` (${data.unread})` : ''}` },
            { value: 'placement', label: 'Placement' },
            { value: 'marks', label: 'Marks' },
            { value: 'skill', label: 'Skills' },
            { value: 'general', label: 'Notices' },
          ]}
        />
        <Button icon={<CheckOutlined />} disabled={!data?.unread} loading={readAll.isPending} onClick={() => readAll.mutate()}>
          Mark all read
        </Button>
      </Space>
      <List
        loading={isFetching}
        dataSource={data?.data}
        locale={{ emptyText: <Empty description={filter === 'unread' ? "You're all caught up" : 'No notifications yet'} /> }}
        pagination={data && data.meta.total > 20 ? { current: page, pageSize: 20, total: data.meta.total, onChange: setPage } : undefined}
        renderItem={(n) => (
          <List.Item
            style={{ background: n.is_read ? undefined : 'var(--accent-soft)', padding: '12px 16px', borderRadius: 8, marginBottom: 4 }}
            actions={[
              !n.is_read && <Button key="r" size="small" type="link" onClick={() => read.mutate(n.id)}>Mark read</Button>,
              <Button key="h" size="small" type="text" icon={<DeleteOutlined />} aria-label="Remove" onClick={() => Modal.confirm({ title: 'Remove this notification from your inbox?', onOk: () => hide.mutateAsync(n.id) })} />,
            ].filter(Boolean)}
          >
            <List.Item.Meta
              title={
                <Space wrap>
                  {!n.is_read && <span style={{ width: 8, height: 8, borderRadius: 4, background: 'var(--accent)', display: 'inline-block' }} />}
                  <a onClick={() => open(n)} style={{ fontWeight: n.is_read ? 400 : 600 }}>{n.title}</a>
                  <TypeTag type={n.type} />
                </Space>
              }
              description={
                <>
                  <Typography.Paragraph style={{ marginBottom: 4 }}>{n.body}</Typography.Paragraph>
                  {n.attachment && (
                    <div style={{ marginBottom: 4 }}>
                      <FileAnchor link={n.attachment} />
                    </div>
                  )}
                  <Typography.Text type="secondary" style={{ fontSize: 12 }}>
                    {n.sender_name ? `From ${n.sender_name} · ` : ''}
                    {dayjs(n.created_at).format('DD MMM YYYY, HH:mm')} ({dayjs(n.created_at).fromNow()})
                  </Typography.Text>
                </>
              }
            />
          </List.Item>
        )}
      />
    </>
  );
}

type Target = SendInput['target_type'];

function SendView() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const [form] = Form.useForm<SendInput & { student?: number }>();
  const [result, setResult] = useState<string>();
  const [error, setError] = useState<string>();
  const [search, setSearch] = useState('');
  const wide = !!user?.roles.some((r) => r === 'admin' || r === 'placement_officer');
  const target = Form.useWatch('target_type', form) as Target | undefined;
  const { data: roles } = useQuery({ queryKey: ['roles'], queryFn: rolesApi.list, enabled: wide });
  const { data: depts } = useDepartments();
  const { data: classes } = useClasses();
  const { data: people } = useQuery({
    queryKey: ['students', 'notify-search', search],
    queryFn: () => studentsApi.list({ page: 1, page_size: 20, search }),
    enabled: target === 'user',
  });

  const [attachment, setAttachment] = useState<UploadedFile>();
  const send = useMutation({
    mutationFn: (v: SendInput) =>
      notificationsApi.send({ ...v, target_id: v.target_type === 'all' ? null : v.target_id, attachment_file_id: attachment?.id }),
    onSuccess: (r) => {
      setResult(`Sent to ${r.recipients} ${r.recipients === 1 ? 'person' : 'people'}.`);
      setError(undefined);
      setAttachment(undefined);
      form.resetFields();
      qc.invalidateQueries({ queryKey: ['notifications'] });
    },
    onError: (e) => {
      setError(errorMessage(e));
      setResult(undefined);
    },
  });

  const targets: { value: Target; label: string }[] = [
    ...(wide ? [{ value: 'all' as Target, label: 'Everyone' }, { value: 'role' as Target, label: 'A role' }] : []),
    { value: 'department', label: 'A department' },
    { value: 'class', label: 'A class' },
    { value: 'user', label: 'One student' },
  ];

  return (
    <div style={{ maxWidth: 640 }}>
      {!wide && <Alert type="info" showIcon style={{ marginBottom: 16 }} title="You can notify your own department, its classes and its students." />}
      {result && <Alert type="success" showIcon closable style={{ marginBottom: 16 }} title={result} onClose={() => setResult(undefined)} />}
      {error && <Alert type="error" showIcon style={{ marginBottom: 16 }} title={error} />}
      <Form form={form} layout="vertical" initialValues={{ type: 'general', target_type: wide ? 'all' : 'class', include_parents: false }} onFinish={(v) => send.mutate(v)} requiredMark="optional">
        <Form.Item name="target_type" label="Send to">
          <Radio.Group optionType="button" options={targets} onChange={() => form.setFieldValue('target_id', undefined)} />
        </Form.Item>
        {target === 'role' && (
          <Form.Item name="target_id" label="Role" rules={[{ required: true }]}>
            <Select options={(roles ?? []).map((r) => ({ value: r.id, label: r.name }))} />
          </Form.Item>
        )}
        {target === 'department' && (
          <Form.Item name="target_id" label="Department" rules={[{ required: true }]}>
            <Select options={(depts ?? []).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
          </Form.Item>
        )}
        {target === 'class' && (
          <Form.Item name="target_id" label="Class" rules={[{ required: true }]}>
            <Select showSearch optionFilterProp="label" options={(classes ?? []).map((c) => ({ value: c.id, label: c.label }))} />
          </Form.Item>
        )}
        {target === 'user' && (
          <Form.Item name="target_id" label="Student" rules={[{ required: true }]}>
            <Select
              showSearch
              filterOption={false}
              onSearch={setSearch}
              placeholder="Search by name or register number"
              options={(people?.data ?? []).map((s) => ({ value: s.id, label: `${s.name} · ${s.register_no}` }))}
            />
          </Form.Item>
        )}
        {target && target !== 'all' && target !== 'role' && (
          <Form.Item name="include_parents" label="Also send to parents" valuePropName="checked">
            <Switch />
          </Form.Item>
        )}
        <Form.Item name="type" label="Category">
          <Segmented options={[{ value: 'general', label: 'General' }, { value: 'placement', label: 'Placement' }, { value: 'marks', label: 'Marks' }, { value: 'skill', label: 'Skills' }]} />
        </Form.Item>
        <Form.Item name="title" label="Title" rules={[{ required: true, whitespace: true }, { max: 200 }]}>
          <Input placeholder="e.g. Internal assessment timetable" />
        </Form.Item>
        <Form.Item name="body" label="Message" rules={[{ required: true, whitespace: true }, { max: 4000 }]}>
          <Input.TextArea rows={5} showCount maxLength={4000} />
        </Form.Item>
        <Form.Item label="Attachment">
          <Space wrap>
            {attachment && <FileAnchor link={attachment} />}
            <UploadButton size="small" category="notification_attachment" onUploaded={(f) => setAttachment(f)}>
              {attachment ? 'Replace' : 'Attach a PDF or image'}
            </UploadButton>
            {attachment && (
              <Button size="small" type="link" danger onClick={() => setAttachment(undefined)}>
                Remove
              </Button>
            )}
          </Space>
        </Form.Item>
        <Button type="primary" htmlType="submit" icon={<SendOutlined />} loading={send.isPending}>
          Send notification
        </Button>
      </Form>
    </div>
  );
}

function SentView() {
  const { data, isLoading } = useQuery({ queryKey: ['notifications', 'sent'], queryFn: notificationsApi.sent });
  return (
    <Table
      rowKey="id"
      size="small"
      loading={isLoading}
      dataSource={data}
      pagination={{ pageSize: 20, hideOnSinglePage: true }}
      scroll={{ x: 760 }}
      expandable={{ expandedRowRender: (n) => <Typography.Paragraph style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{n.body}</Typography.Paragraph> }}
      columns={[
        { title: 'Sent', dataIndex: 'created_at', width: 150, render: (v) => dayjs(v).format('DD MMM YY, HH:mm') },
        { title: 'Title', dataIndex: 'title', render: (v, n) => <Space wrap>{v}<TypeTag type={n.type} />{n.attachment && <FileAnchor link={n.attachment} label="attachment" />}</Space> },
        { title: 'To', dataIndex: 'target_label', width: 150 },
        { title: 'By', dataIndex: 'sender_name', width: 150 },
        { title: 'Read', width: 120, render: (_, n) => `${n.read_count} / ${n.recipients}` },
      ]}
    />
  );
}

export default function NotificationsPage() {
  const { can } = useAuth();
  if (!can('notification.create')) {
    return (
      <Card>
        <InboxView />
      </Card>
    );
  }
  return (
    <Card>
      <Tabs
        items={[
          { key: 'inbox', label: 'Inbox', children: <InboxView /> },
          { key: 'send', label: 'Send notification', children: <SendView /> },
          { key: 'sent', label: 'Sent', children: <SentView /> },
        ]}
      />
    </Card>
  );
}

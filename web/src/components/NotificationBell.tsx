import { Badge, Button, Dropdown, Empty, List, Space, Spin, Tag, Typography } from 'antd';
import { BellOutlined, PaperClipOutlined } from '@ant-design/icons';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import { useNavigate } from 'react-router-dom';
import { noticeLink, notificationsApi, TYPE_COLORS, type Notice } from '../api/notifications';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';

dayjs.extend(relativeTime);

/** Header bell: unread badge (polled every minute) and the latest notifications. */
export default function NotificationBell() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const staff = ['admin', 'staff'].includes(audienceOf(user?.roles ?? []));
  const { data: unread = 0 } = useQuery({ queryKey: ['notifications', 'unread'], queryFn: notificationsApi.unreadCount, refetchInterval: 60_000 });
  const { data: latest, isLoading, refetch } = useQuery({
    queryKey: ['notifications', 'latest'],
    queryFn: () => notificationsApi.inbox({ page: 1, page_size: 8 }),
    enabled: false,
  });
  const read = useMutation({
    mutationFn: (n: Notice) => notificationsApi.markRead(n.id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['notifications'] }),
  });

  const open = (n: Notice) => {
    if (!n.is_read) read.mutate(n);
    const link = noticeLink(n, staff);
    navigate(link ?? '/notifications');
  };

  const panel = (
    <div style={{ width: 360, maxWidth: '90vw', background: 'var(--ant-color-bg-elevated, #fff)', borderRadius: 8, boxShadow: '0 6px 16px rgba(0,0,0,.12)' }}>
      <Space style={{ width: '100%', justifyContent: 'space-between', padding: '10px 14px', borderBottom: '1px solid #f0f0f0' }}>
        <Typography.Text strong>Notifications</Typography.Text>
        {unread > 0 && (
          <Button size="small" type="link" onClick={() => notificationsApi.readAll().then(() => qc.invalidateQueries({ queryKey: ['notifications'] }))}>
            Mark all read
          </Button>
        )}
      </Space>
      {isLoading ? (
        <div style={{ padding: 24, textAlign: 'center' }}><Spin /></div>
      ) : !latest?.data.length ? (
        <Empty style={{ padding: 16 }} description="You're all caught up" />
      ) : (
        <List
          size="small"
          dataSource={latest.data}
          style={{ maxHeight: 420, overflow: 'auto' }}
          renderItem={(n) => (
            <List.Item onClick={() => open(n)} style={{ cursor: 'pointer', padding: '10px 14px', background: n.is_read ? undefined : 'var(--accent-soft)' }}>
              <div style={{ width: '100%' }}>
                <Space style={{ width: '100%', justifyContent: 'space-between' }} align="start">
                  <Typography.Text strong={!n.is_read} ellipsis style={{ maxWidth: 250 }}>{n.title}</Typography.Text>
                  <Typography.Text type="secondary" style={{ fontSize: 12, whiteSpace: 'nowrap' }}>{dayjs(n.created_at).fromNow(true)}</Typography.Text>
                </Space>
                <Typography.Paragraph type="secondary" ellipsis={{ rows: 2 }} style={{ margin: 0, fontSize: 13 }}>{n.body}</Typography.Paragraph>
                {n.attachment && <PaperClipOutlined style={{ color: '#999' }} title={n.attachment.name} />}
              </div>
            </List.Item>
          )}
        />
      )}
      <div style={{ textAlign: 'center', padding: 8, borderTop: '1px solid #f0f0f0' }}>
        <Button type="link" onClick={() => navigate('/notifications')}>View all</Button>
      </div>
    </div>
  );

  return (
    <Dropdown trigger={['click']} popupRender={() => panel} onOpenChange={(o) => o && refetch()} placement="bottomRight">
      <Badge count={unread} size="small" overflowCount={99}>
        <Button type="text" shape="circle" icon={<BellOutlined style={{ fontSize: 18 }} />} aria-label={`Notifications, ${unread} unread`} />
      </Badge>
    </Dropdown>
  );
}

export function TypeTag({ type }: { type: string }) {
  return <Tag color={TYPE_COLORS[type]} style={{ marginInlineEnd: 0 }}>{type}</Tag>;
}

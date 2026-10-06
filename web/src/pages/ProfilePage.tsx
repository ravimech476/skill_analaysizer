import { useState } from 'react';
import { Alert, Button, Card, Col, Descriptions, Form, Input, Row, Tag, message } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { authApi, usersApi } from '../api/endpoints';
import { errorMessage } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { ROLE_COLORS } from '../auth/access';
import { filesApi } from '../api/files';
import { UploadButton, UserAvatar } from '../components/Files';
import { Space } from 'antd';

export default function ProfilePage() {
  const { user, can, reload } = useAuth();
  const setPhoto = (id: number | null) =>
    filesApi.setMyPhoto(id).then(() => {
      message.success(id ? 'Photo updated' : 'Photo removed');
      return reload();
    }, (e) => message.error(errorMessage(e)));
  const [form] = Form.useForm();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string>();

  // Full record needs user.view; everyone else sees the session info.
  const { data: full } = useQuery({
    queryKey: ['users', user?.id],
    queryFn: () => usersApi.get(user!.id),
    enabled: !!user && can('user.view'),
  });

  const change = async (v: { current_password?: string; new_password: string }) => {
    setSaving(true);
    setError(undefined);
    try {
      await authApi.changePassword(v.current_password ?? '', v.new_password);
      message.success('Password changed');
      form.resetFields();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Row gutter={[16, 16]}>
      <Col xs={24} lg={14}>
        <Card>
          <Space size="large" style={{ marginBottom: 16 }}>
            <UserAvatar name={user?.name} photo={user?.photo} size={72} />
            <Space wrap>
              <UploadButton category="profile_photo" onUploaded={(f) => setPhoto(f.id)}>
                {user?.photo ? 'Change photo' : 'Upload photo'}
              </UploadButton>
              {user?.photo && (
                <Button danger onClick={() => setPhoto(null)}>
                  Remove
                </Button>
              )}
            </Space>
          </Space>
          <Descriptions column={1} bordered size="small">
            <Descriptions.Item label="Name">{user?.name}</Descriptions.Item>
            <Descriptions.Item label="Username">{user?.username}</Descriptions.Item>
            {full && <Descriptions.Item label="Mobile">{full.mobile ?? '—'}</Descriptions.Item>}
            {full && <Descriptions.Item label="Email">{full.email ?? '—'}</Descriptions.Item>}
            <Descriptions.Item label="Roles">
              {user?.roles.map((r) => (
                <Tag key={r} color={ROLE_COLORS[r]}>
                  {r.replace('_', ' ')}
                </Tag>
              ))}
            </Descriptions.Item>
          </Descriptions>
        </Card>
      </Col>
      <Col xs={24} lg={10}>
        <Card title="Change password">
          {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
          <Form form={form} layout="vertical" onFinish={change} requiredMark={false}>
            <Form.Item
              name="current_password"
              label="Current password"
              extra="Leave empty if you have only ever signed in with OTP."
            >
              <Input.Password autoComplete="current-password" />
            </Form.Item>
            <Form.Item name="new_password" label="New password" rules={[{ required: true, min: 8, message: 'At least 8 characters' }]}>
              <Input.Password autoComplete="new-password" />
            </Form.Item>
            <Button type="primary" htmlType="submit" loading={saving}>
              Update password
            </Button>
          </Form>
        </Card>
      </Col>
    </Row>
  );
}

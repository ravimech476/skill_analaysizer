import { useEffect, useState } from 'react';
import { Alert, Button, Form, Input, Tabs, Typography, message } from 'antd';
import { LockOutlined, MobileOutlined, UserOutlined } from '@ant-design/icons';
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { authApi } from '../api/endpoints';
import { errorMessage } from '../api/client';
import type { OTPSent } from '../api/types';
import { useAuth } from '../auth/AuthContext';
import { AuthShell } from '../components/AuthShell';

export function useCountdown() {
  const [left, setLeft] = useState(0);
  useEffect(() => {
    if (left <= 0) return;
    const t = setTimeout(() => setLeft((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [left]);
  return [left, setLeft] as const;
}

function PasswordLogin({ onDone }: { onDone: () => void }) {
  const { startSession } = useAuth();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();

  const submit = async (v: { username: string; password: string }) => {
    setLoading(true);
    setError(undefined);
    try {
      startSession(await authApi.login(v.username.trim(), v.password));
      onDone();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Form layout="vertical" onFinish={submit} requiredMark={false} size="large">
      {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
      <Form.Item name="username" label="Username or email" rules={[{ required: true, message: 'Enter your username' }]}>
        <Input prefix={<UserOutlined />} autoComplete="username" autoFocus />
      </Form.Item>
      <Form.Item name="password" label="Password" rules={[{ required: true, message: 'Enter your password' }]}>
        <Input.Password prefix={<LockOutlined />} autoComplete="current-password" />
      </Form.Item>
      <div style={{ textAlign: 'right', marginTop: -8, marginBottom: 16 }}>
        <Link to="/forgot-password">Forgot password?</Link>
      </div>
      <Button type="primary" htmlType="submit" block loading={loading}>
        Log in
      </Button>
    </Form>
  );
}

function OtpLogin({ onDone }: { onDone: () => void }) {
  const { startSession } = useAuth();
  const [identifier, setIdentifier] = useState('');
  const [sent, setSent] = useState<OTPSent | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();
  const [left, setLeft] = useCountdown();

  const send = async (id: string) => {
    setLoading(true);
    setError(undefined);
    try {
      const res = await authApi.requestOtp(id.trim());
      setIdentifier(id.trim());
      setSent(res);
      setLeft(60);
      message.success(res.message);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  const verify = async (v: { otp: string }) => {
    setLoading(true);
    setError(undefined);
    try {
      startSession(await authApi.verifyOtp(identifier, v.otp));
      onDone();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  if (!sent) {
    return (
      <Form layout="vertical" onFinish={(v) => send(v.identifier)} requiredMark={false} size="large">
        {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
        <Form.Item
          name="identifier"
          label="Username or mobile number"
          extra="If your mobile is shared with a family member, use your username."
          rules={[{ required: true, message: 'Enter your username or mobile' }]}
        >
          <Input prefix={<MobileOutlined />} autoFocus />
        </Form.Item>
        <Button type="primary" htmlType="submit" block loading={loading}>
          Send OTP
        </Button>
      </Form>
    );
  }

  return (
    <Form layout="vertical" onFinish={verify} requiredMark={false} size="large">
      {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
      <Typography.Paragraph type="secondary">
        {sent.masked_mobile ? `Enter the 6-digit code sent to ${sent.masked_mobile}.` : sent.message}
      </Typography.Paragraph>
      {sent.debug_otp && (
        <Alert type="info" showIcon style={{ marginBottom: 16 }} title={`Development mode: OTP is ${sent.debug_otp}`} />
      )}
      <Form.Item name="otp" label="OTP" rules={[{ required: true, pattern: /^\d{6}$/, message: 'Enter the 6-digit OTP' }]}>
        <Input.OTP length={6} autoFocus />
      </Form.Item>
      <Button type="primary" htmlType="submit" block loading={loading}>
        Verify & log in
      </Button>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 12 }}>
        <Button type="link" style={{ padding: 0 }} onClick={() => setSent(null)}>
          Change number
        </Button>
        <Button type="link" style={{ padding: 0 }} disabled={left > 0} onClick={() => send(identifier)}>
          {left > 0 ? `Resend in ${left}s` : 'Resend OTP'}
        </Button>
      </div>
    </Form>
  );
}

export default function LoginPage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from ?? '/';

  if (user) return <Navigate to={from} replace />;
  const done = () => navigate(from, { replace: true });

  return (
    <AuthShell>
      <Typography.Title level={2} style={{ marginTop: 0, marginBottom: 4 }}>
        Welcome back
      </Typography.Title>
      <Typography.Paragraph type="secondary" style={{ fontSize: 15 }}>
        Sign in to your college account.
      </Typography.Paragraph>
      <Tabs
        items={[
          { key: 'password', label: 'Password', children: <PasswordLogin onDone={done} /> },
          { key: 'otp', label: 'One-time code', children: <OtpLogin onDone={done} /> },
        ]}
      />
    </AuthShell>
  );
}

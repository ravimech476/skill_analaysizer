import { useState } from 'react';
import { Alert, Button, Form, Input, Result, Typography } from 'antd';
import { Link, useNavigate } from 'react-router-dom';
import { authApi } from '../api/endpoints';
import { errorMessage } from '../api/client';
import type { OTPSent } from '../api/types';
import { AuthShell } from '../components/AuthShell';
import { useCountdown } from './LoginPage';

export default function ForgotPasswordPage() {
  const navigate = useNavigate();
  const [identifier, setIdentifier] = useState('');
  const [sent, setSent] = useState<OTPSent | null>(null);
  const [done, setDone] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();
  const [left, setLeft] = useCountdown();

  const send = async (id: string) => {
    setLoading(true);
    setError(undefined);
    try {
      setSent(await authApi.forgotPassword(id.trim()));
      setIdentifier(id.trim());
      setLeft(60);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  const reset = async (v: { otp: string; password: string }) => {
    setLoading(true);
    setError(undefined);
    try {
      await authApi.resetPassword(identifier, v.otp, v.password);
      setDone(true);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthShell>
      <div>
        {done ? (
          <Result
            status="success"
            title="Password reset"
            subTitle="You have been signed out of all devices. Log in with your new password."
            extra={<Button type="primary" onClick={() => navigate('/login')}>Go to login</Button>}
          />
        ) : (
          <>
            <Typography.Title level={2} style={{ marginTop: 0, marginBottom: 4 }}>
              Reset password
            </Typography.Title>
            <Typography.Paragraph type="secondary" style={{ fontSize: 15 }}>
              We will send a one-time code to your registered mobile number.
            </Typography.Paragraph>
            {error && <Alert type="error" title={error} showIcon style={{ marginBottom: 16 }} />}
            {!sent ? (
              <Form layout="vertical" size="large" requiredMark={false} onFinish={(v) => send(v.identifier)}>
                <Form.Item name="identifier" label="Username or mobile number" rules={[{ required: true }]}>
                  <Input autoFocus />
                </Form.Item>
                <Button type="primary" htmlType="submit" block loading={loading}>
                  Send OTP
                </Button>
              </Form>
            ) : (
              <Form layout="vertical" size="large" requiredMark={false} onFinish={reset}>
                <Typography.Paragraph type="secondary">
                  {sent.masked_mobile ? `OTP sent to ${sent.masked_mobile}.` : sent.message}
                </Typography.Paragraph>
                {sent.debug_otp && (
                  <Alert type="info" showIcon style={{ marginBottom: 16 }} title={`Development mode: OTP is ${sent.debug_otp}`} />
                )}
                <Form.Item name="otp" label="OTP" rules={[{ required: true, pattern: /^\d{6}$/, message: 'Enter the 6-digit OTP' }]}>
                  <Input.OTP length={6} />
                </Form.Item>
                <Form.Item name="password" label="New password" rules={[{ required: true, min: 8, message: 'At least 8 characters' }]}>
                  <Input.Password autoComplete="new-password" />
                </Form.Item>
                <Form.Item
                  name="confirm"
                  label="Confirm password"
                  dependencies={['password']}
                  rules={[
                    { required: true },
                    ({ getFieldValue }) => ({
                      validator: (_, v) =>
                        v === getFieldValue('password') ? Promise.resolve() : Promise.reject(new Error('Passwords do not match')),
                    }),
                  ]}
                >
                  <Input.Password autoComplete="new-password" />
                </Form.Item>
                <Button type="primary" htmlType="submit" block loading={loading}>
                  Reset password
                </Button>
                <Button type="link" block disabled={left > 0} onClick={() => send(identifier)} style={{ marginTop: 8 }}>
                  {left > 0 ? `Resend in ${left}s` : 'Resend OTP'}
                </Button>
              </Form>
            )}
            <div style={{ marginTop: 16, textAlign: 'center' }}>
              <Link to="/login">Back to login</Link>
            </div>
          </>
        )}
      </div>
    </AuthShell>
  );
}

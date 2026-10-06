import { Result } from 'antd';
import { useAuth } from '../auth/AuthContext';
import { audienceOf, type Feature } from '../auth/access';

export default function ComingSoonPage({ feature }: { feature: Feature }) {
  const { user } = useAuth();
  const audience = audienceOf(user?.roles ?? []);
  return (
    <Result
      status="info"
      title={feature.label[audience]}
      subTitle={`${feature.description[audience]}. This module is being built next.`}
    />
  );
}

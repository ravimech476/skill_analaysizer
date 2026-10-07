import { useState } from 'react';
import {
  Button,
  Card,
  Col,
  Input,
  List,
  Progress,
  Row,
  Space,
  Statistic,
  Table,
  Tag,
  Typography,
} from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import { exportsApi } from '../api/reports';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { useAuth } from '../auth/AuthContext';
import { audienceOf } from '../auth/access';
import { filesApi } from '../api/files';
import { FileSlot } from '../components/Files';
import { lpa, placementApi } from '../api/placement';
import { StudentPicker, OpportunitiesView } from './PlacementPage';

function Placed() {
  const { can } = useAuth();
  const qc = useQueryClient();
  const [batch, setBatch] = useState<string>();
  const [search, setSearch] = useState('');
  const { data: stats } = useQuery({ queryKey: ['placements', 'stats', batch], queryFn: () => placementApi.stats(batch) });
  const { data: list, isFetching } = useQuery({ queryKey: ['placements', batch, search], queryFn: () => placementApi.placements({ batch, search }) });

  return (
    <>
      <Space wrap style={{ marginBottom: 16 }}>
        <Input placeholder="Batch e.g. 2025-2029" allowClear style={{ width: 200 }} onPressEnter={(e) => setBatch((e.target as HTMLInputElement).value || undefined)} onChange={(e) => !e.target.value && setBatch(undefined)} />
        <Input.Search allowClear placeholder="Student or company" style={{ width: 240 }} onSearch={setSearch} />
        <Button icon={<DownloadOutlined />} onClick={() => exportsApi.placements({ batch, search: search || undefined })}>
          Placement report (.xlsx)
        </Button>
      </Space>
      {stats && (
        <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Placed" value={stats.placed_percent} suffix="%" /><Typography.Text type="secondary">{stats.placed_students} of {stats.total_students} students</Typography.Text></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Offers" value={stats.total_offers} /></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Highest" value={stats.highest_package ?? 0} suffix="LPA" /></Card></Col>
          <Col xs={12} md={6}><Card size="small"><Statistic title="Average (best offer)" value={stats.average_package ?? 0} suffix="LPA" /></Card></Col>
          <Col xs={24} lg={12}>
            <Card size="small" title="By department">
              <List
                size="small"
                dataSource={stats.by_department}
                renderItem={(d) => (
                  <List.Item>
                    <div style={{ width: '100%' }}>
                      <Space style={{ width: '100%', justifyContent: 'space-between' }}><span><b>{d.code}</b> {d.name}</span><span>{d.placed}/{d.students}</span></Space>
                      <Progress percent={d.percent} size="small" />
                    </div>
                  </List.Item>
                )}
              />
            </Card>
          </Col>
          <Col xs={24} lg={12}>
            <Card size="small" title="By company">
              <Table size="small" rowKey="company" pagination={false} dataSource={stats.by_company} locale={{ emptyText: 'No placements yet' }}
                columns={[{ title: 'Company', dataIndex: 'company' }, { title: 'Offers', dataIndex: 'offers', width: 80 }, { title: 'Highest', dataIndex: 'highest', width: 110, render: (v) => lpa(v) }]} />
            </Card>
          </Col>
        </Row>
      )}
      <Table
        rowKey="id"
        size="small"
        loading={isFetching}
        dataSource={list}
        pagination={{ pageSize: 25, hideOnSinglePage: true }}
        scroll={{ x: 760 }}
        columns={[
          { title: 'Student', render: (_, p) => <span>{p.student_name} <Typography.Text type="secondary">{p.register_no}</Typography.Text></span> },
          { title: 'Dept', dataIndex: 'department_code', width: 80 },
          { title: 'Batch', dataIndex: 'batch', width: 110 },
          { title: 'Company', dataIndex: 'company_name' },
          { title: 'Role', dataIndex: 'job_title', width: 180 },
          { title: 'Package', dataIndex: 'package_lpa', width: 110, render: (v) => lpa(v) },
          { title: 'Offer date', dataIndex: 'offer_date', width: 110, render: (v) => (v ? dayjs(v).format('DD MMM YY') : '—') },
          {
            title: 'Offer letter',
            width: 200,
            render: (_, p) => (
              <FileSlot
                category="offer_letter"
                value={p.offer_letter}
                canEdit={can('placement.update')}
                emptyText="—"
                save={(fid) => filesApi.setOfferLetter(p.id, fid).then(() => qc.invalidateQueries({ queryKey: ['placements'] }))}
              />
            ),
          },
        ]}
      />
    </>
  );
}

export default function PlacementHistoryPage() {
  const { user } = useAuth();
  const audience = audienceOf(user?.roles ?? []);

  if (audience === 'student' || audience === 'parent') {
    return (
      <Card>
        <StudentPicker parent={audience === 'parent'}>
          {(id) => <OpportunitiesView studentId={id} mode="drives" />}
        </StudentPicker>
      </Card>
    );
  }

  return (
    <Card>
      <Placed />
    </Card>
  );
}

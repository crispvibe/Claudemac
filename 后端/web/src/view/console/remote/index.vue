<template>
  <div class="remote-page">
    <header class="page-heading">
      <div>
        <span class="page-kicker">远程管理</span>
        <h2>{{ pageMeta.title }}</h2>
        <p>{{ pageMeta.description }}</p>
      </div>
      <div class="page-actions">
        <el-button v-if="pageKey === 'users'" type="primary" icon="plus" @click="openUser()">新增用户</el-button>
        <el-button v-if="pageKey === 'legalDocuments'" type="primary" icon="plus" @click="openLegalDocument()">新增协议</el-button>
        <el-button v-if="pageKey === 'appUpdates'" type="primary" icon="plus" @click="openAppUpdate()">新增版本</el-button>
      </div>
    </header>

    <template v-if="pageKey === 'users'">
      <section class="section-grid user-layout">
        <div class="work-panel">
          <div class="filter-panel compact-filter">
            <el-form :inline="true" :model="users.search">
              <el-form-item label="邮箱"><el-input v-model="users.search.email" clearable placeholder="邮箱" /></el-form-item>
              <el-form-item label="状态">
                <el-select v-model="users.search.status" clearable placeholder="全部">
                  <el-option label="正常" value="active" />
                  <el-option label="禁用" value="disabled" />
                </el-select>
              </el-form-item>
              <el-form-item>
                <el-button type="primary" icon="search" @click="reload(users)">查询</el-button>
                <el-button icon="refresh" @click="reset(users)">重置</el-button>
              </el-form-item>
            </el-form>
          </div>

          <el-table :data="users.list" highlight-current-row row-key="id" @current-change="selectUser">
            <el-table-column prop="id" label="ID" width="80" />
            <el-table-column label="账号" min-width="240">
              <template #default="{ row }">
                <div class="identity-cell">
                  <strong>{{ row.email || '-' }}</strong>
                </div>
              </template>
            </el-table-column>
            <el-table-column prop="status" label="状态" width="120">
              <template #default="{ row }">
                <el-switch
                  v-model="row.status"
                  active-value="active"
                  inactive-value="disabled"
                  @change="updateUserStatus(row)"
                />
              </template>
            </el-table-column>
            <el-table-column prop="lastLoginAt" label="最近登录" min-width="180" />
            <el-table-column prop="CreatedAt" label="创建时间" min-width="180" />
            <el-table-column label="操作" fixed="right" width="280">
              <template #default="{ row }">
                <el-button type="primary" link icon="edit" @click.stop="openUser(row)">编辑</el-button>
                <el-button type="primary" link icon="switch-button" @click.stop="kick(row)">踢下线</el-button>
                <el-button type="danger" link icon="lock" @click.stop="ban(row)">封禁</el-button>
                <el-button type="danger" link icon="delete" @click.stop="removeUser(row)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
          <Pager :state="users" />
        </div>

        <aside class="work-panel user-side">
          <div class="panel-title">
            <div>
              <h3>用户上下文</h3>
              <span>{{ selectedUser ? `用户 ID ${selectedUser.id}` : '从左侧列表选择用户后可管理设备。' }}</span>
            </div>
          </div>
          <el-empty v-if="!selectedUser" description="未选择用户" />
          <template v-else>
            <div class="user-summary">
              <div>
                <span>邮箱</span>
                <strong>{{ selectedUser.email || '-' }}</strong>
              </div>
              <div>
                <span>状态</span>
                <strong>{{ statusText(selectedUser.status) }}</strong>
              </div>
              <div>
                <span>最近登录</span>
                <strong>{{ selectedUser.lastLoginAt || '-' }}</strong>
              </div>
            </div>

            <div class="detail-block">
              <div class="detail-heading">
                <h4>设备</h4>
                <el-button type="primary" link icon="refresh" @click="reload(devices)">刷新</el-button>
              </div>
              <el-table :data="devices.list" size="small" empty-text="暂无设备">
                <el-table-column prop="deviceName" label="设备" min-width="140" />
                <el-table-column prop="deviceType" label="类型" width="90" />
                <el-table-column label="远程" width="80">
                  <template #default="{ row }">
                    <el-switch v-model="row.remoteEnabled" @change="updateDevice(row)" />
                  </template>
                </el-table-column>
                <el-table-column label="状态" width="90">
                  <template #default="{ row }">
                    <el-switch v-model="row.status" active-value="active" inactive-value="disabled" @change="updateDevice(row)" />
                  </template>
                </el-table-column>
              </el-table>
            </div>
          </template>
        </aside>
      </section>
    </template>

    <template v-else-if="pageKey === 'devices'">
      <section class="work-panel">
        <div class="filter-panel compact-filter">
          <el-form :inline="true" :model="devices.search">
            <el-form-item label="用户ID"><el-input-number v-model="devices.search.userId" :min="0" /></el-form-item>
            <el-form-item label="设备名"><el-input v-model="devices.search.deviceName" clearable placeholder="设备名" /></el-form-item>
            <el-form-item label="类型">
              <el-select v-model="devices.search.deviceType" clearable placeholder="全部">
                <el-option label="desktop" value="desktop" />
                <el-option label="ios" value="ios" />
              </el-select>
            </el-form-item>
            <el-form-item label="状态">
              <el-select v-model="devices.search.status" clearable placeholder="全部">
                <el-option label="正常" value="active" />
                <el-option label="禁用" value="disabled" />
              </el-select>
            </el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(devices)">查询</el-button>
              <el-button icon="refresh" @click="reset(devices)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <el-table :data="devices.list" row-key="id">
          <el-table-column prop="id" label="ID" width="80" />
          <el-table-column prop="userId" label="用户ID" width="100" />
          <el-table-column prop="deviceName" label="设备名" min-width="160" />
          <el-table-column prop="deviceType" label="类型" width="100" />
          <el-table-column prop="platform" label="平台" width="100" />
          <el-table-column label="在线" width="90">
            <template #default="{ row }">
              <el-tag :type="row.online ? 'success' : 'info'" effect="plain">{{ row.online ? '在线' : '离线' }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column label="连接策略" min-width="170">
            <template #default="{ row }">
              <el-select v-model="row.approvalPolicy" size="small" @change="updateDevice(row)">
                <el-option label="每次询问" value="always_ask" />
                <el-option label="允许所有人" value="allow_anyone" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="远程" width="90">
            <template #default="{ row }">
              <el-switch v-model="row.remoteEnabled" @change="updateDevice(row)" />
            </template>
          </el-table-column>
          <el-table-column label="状态" width="100">
            <template #default="{ row }">
              <el-switch v-model="row.status" active-value="active" inactive-value="disabled" @change="updateDevice(row)" />
            </template>
          </el-table-column>
          <el-table-column prop="lastSeenAt" label="最近在线" min-width="180" />
          <el-table-column label="操作" fixed="right" width="160">
            <template #default="{ row }">
              <el-button type="primary" link icon="switch-button" @click="kickDevice(row)">踢设备</el-button>
              <el-button type="danger" link icon="delete" @click="removeDevice(row)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
        <Pager :state="devices" />
      </section>
    </template>

    <template v-else-if="pageKey === 'connections'">
      <section class="work-panel">
        <div class="filter-panel compact-filter">
          <el-form :inline="true" :model="connections.search">
            <el-form-item label="发起用户"><el-input-number v-model="connections.search.fromUserId" :min="0" /></el-form-item>
            <el-form-item label="目标用户"><el-input-number v-model="connections.search.toUserId" :min="0" /></el-form-item>
            <el-form-item label="目标设备"><el-input-number v-model="connections.search.toDeviceId" :min="0" /></el-form-item>
            <el-form-item label="状态"><el-input v-model="connections.search.status" clearable placeholder="pending / accepted / rejected" /></el-form-item>
            <el-form-item label="传输"><el-input v-model="connections.search.transport" clearable placeholder="lan / p2p / turn" /></el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(connections)">查询</el-button>
              <el-button icon="refresh" @click="reset(connections)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <RemoteTable :state="connections" :columns="connectionColumns">
          <template #operate="{ row }">
            <el-button type="danger" link icon="delete" @click="removeConnection(row)">删除</el-button>
          </template>
        </RemoteTable>
      </section>
    </template>

    <template v-else-if="pageKey === 'codeAttempts'">
      <section class="work-panel">
        <div class="filter-panel compact-filter">
          <el-form :inline="true" :model="codeAttempts.search">
            <el-form-item label="目标设备"><el-input-number v-model="codeAttempts.search.targetDeviceId" :min="0" /></el-form-item>
            <el-form-item label="发起用户"><el-input-number v-model="codeAttempts.search.fromUserId" :min="0" /></el-form-item>
            <el-form-item label="状态"><el-input v-model="codeAttempts.search.status" clearable /></el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(codeAttempts)">查询</el-button>
              <el-button icon="refresh" @click="reset(codeAttempts)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <RemoteTable :state="codeAttempts" :columns="codeAttemptColumns">
          <template #operate="{ row }">
            <el-button type="danger" link icon="delete" @click="removeCodeAttempt(row)">删除</el-button>
          </template>
        </RemoteTable>
      </section>
    </template>

    <template v-else-if="pageKey === 'accountDeletions'">
      <section class="work-panel">
        <div class="filter-panel compact-filter">
          <el-form :inline="true" :model="deletions.search">
            <el-form-item label="用户ID"><el-input-number v-model="deletions.search.userId" :min="0" /></el-form-item>
            <el-form-item label="脱敏邮箱"><el-input v-model="deletions.search.emailMasked" clearable placeholder="例如 a***e@example.com" /></el-form-item>
            <el-form-item label="触发方">
              <el-select v-model="deletions.search.operator" clearable placeholder="全部">
                <el-option label="用户自助" value="self" />
                <el-option label="后台处理" value="admin" />
              </el-select>
            </el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(deletions)">查询</el-button>
              <el-button icon="refresh" @click="reset(deletions)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <RemoteTable :state="deletions" :columns="deletionColumns">
          <template #operate="{ row }">
            <el-button type="primary" link icon="view" @click="openDeletion(row)">详情</el-button>
          </template>
        </RemoteTable>
      </section>
    </template>

    <template v-else-if="pageKey === 'legalDocuments'">
      <section class="work-panel">
        <div class="filter-panel compact-filter">
          <el-form :inline="true" :model="legalDocuments.search">
            <el-form-item label="类型">
              <el-select v-model="legalDocuments.search.type" clearable placeholder="全部">
                <el-option label="隐私政策" value="privacy_policy" />
                <el-option label="用户协议" value="user_agreement" />
              </el-select>
            </el-form-item>
            <el-form-item label="平台">
              <el-select v-model="legalDocuments.search.platform" clearable placeholder="全部">
                <el-option label="全部平台" value="all" />
                <el-option label="iOS" value="ios" />
                <el-option label="macOS" value="macos" />
                <el-option label="Windows" value="windows" />
              </el-select>
            </el-form-item>
            <el-form-item label="发布">
              <el-select v-model="legalDocuments.search.published" clearable placeholder="全部">
                <el-option label="已发布" :value="true" />
                <el-option label="未发布" :value="false" />
              </el-select>
            </el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(legalDocuments)">查询</el-button>
              <el-button icon="refresh" @click="reset(legalDocuments)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <RemoteTable :state="legalDocuments" :columns="legalDocumentColumns">
          <template #operate="{ row }">
            <el-button type="primary" link icon="edit" @click="openLegalDocument(row)">编辑</el-button>
            <el-button type="danger" link icon="delete" @click="removeLegalDocument(row)">删除</el-button>
          </template>
        </RemoteTable>
      </section>
    </template>

    <template v-else-if="pageKey === 'appFooter'">
      <section class="section-grid footer-layout">
        <div class="work-panel">
          <div class="panel-title">
            <div>
              <h3>页脚内容</h3>
              <span>登录页、注册页和设置页底部展示同一份 iOS 页脚配置。</span>
            </div>
            <el-button type="primary" :loading="savingAppFooter" @click="submitAppFooter">保存</el-button>
          </div>
          <el-form label-width="112px" :model="appFooterForm">
            <el-form-item label="平台">
              <el-select v-model="appFooterForm.platform" @change="loadAppFooter">
                <el-option label="iOS" value="ios" />
                <el-option label="macOS" value="macos" />
                <el-option label="全平台兜底" value="all" />
              </el-select>
            </el-form-item>
            <el-form-item label="公司名称"><el-input v-model="appFooterForm.companyName" placeholder="禾屿科技" /></el-form-item>
            <el-form-item label="版权文案"><el-input v-model="appFooterForm.copyrightText" placeholder="© 2026 禾屿科技" /></el-form-item>
            <el-form-item label="ICP备案"><el-input v-model="appFooterForm.icpText" placeholder="ICP备案号" /></el-form-item>
            <el-form-item label="公安备案"><el-input v-model="appFooterForm.recordText" clearable placeholder="可选" /></el-form-item>
            <el-form-item label="支持地址"><el-input v-model="appFooterForm.supportUrl" clearable placeholder="可选" /></el-form-item>
            <el-form-item label="隐私地址"><el-input v-model="appFooterForm.privacyUrl" clearable placeholder="可选" /></el-form-item>
            <el-form-item label="启用"><el-switch v-model="appFooterForm.published" /></el-form-item>
          </el-form>
        </div>
        <aside class="work-panel footer-preview">
          <div class="panel-title">
            <div>
              <h3>App 预览</h3>
              <span>客户端会按行展示非空文案。</span>
            </div>
          </div>
          <div class="footer-lines">
            <strong>{{ appFooterForm.companyName || '禾屿科技' }}</strong>
            <span>{{ appFooterForm.copyrightText || '© 2026 禾屿科技' }}</span>
            <span>{{ appFooterForm.icpText || 'ICP备案信息待更新' }}</span>
            <span v-if="appFooterForm.recordText">{{ appFooterForm.recordText }}</span>
          </div>
        </aside>
      </section>
    </template>

    <template v-else-if="pageKey === 'appUpdates'">
      <section class="work-panel">
        <div class="filter-panel compact-filter">
          <el-form :inline="true" :model="appUpdates.search">
            <el-form-item label="平台">
              <el-select v-model="appUpdates.search.platform" clearable placeholder="全部">
                <el-option label="Android" value="android" />
                <el-option label="Windows" value="windows" />
                <el-option label="macOS" value="macos" />
                <el-option label="iOS" value="ios" />
                <el-option label="全平台兜底" value="all" />
              </el-select>
            </el-form-item>
            <el-form-item label="通道">
              <el-select v-model="appUpdates.search.channel" clearable placeholder="全部">
                <el-option label="stable" value="stable" />
                <el-option label="beta" value="beta" />
              </el-select>
            </el-form-item>
            <el-form-item label="架构">
              <el-select v-model="appUpdates.search.packageArch" clearable placeholder="全部">
                <el-option label="Universal" value="universal" />
                <el-option label="Apple Silicon" value="arm64" />
                <el-option label="Intel" value="x86_64" />
              </el-select>
            </el-form-item>
            <el-form-item label="发布">
              <el-select v-model="appUpdates.search.published" clearable placeholder="全部">
                <el-option label="已发布" :value="true" />
                <el-option label="未发布" :value="false" />
              </el-select>
            </el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(appUpdates)">查询</el-button>
              <el-button icon="refresh" @click="reset(appUpdates)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <el-table :data="appUpdates.list" row-key="id">
          <el-table-column prop="id" label="ID" width="80" />
          <el-table-column prop="platform" label="平台" width="100" />
          <el-table-column prop="channel" label="通道" width="100" />
          <el-table-column prop="packageArch" label="架构" width="130" />
          <el-table-column prop="version" label="版本" width="120" />
          <el-table-column prop="buildNumber" label="构建号" width="120" />
          <el-table-column prop="updateType" label="方式" width="110" />
          <el-table-column label="发布" width="90">
            <template #default="{ row }">
              <el-tag :type="row.published ? 'success' : 'info'" effect="plain">{{ row.published ? '已发布' : '未发布' }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="downloadUrl" label="下载链接" min-width="220" show-overflow-tooltip />
          <el-table-column prop="releasedAt" label="发布时间" min-width="180" />
          <el-table-column label="操作" fixed="right" width="150">
            <template #default="{ row }">
              <el-button type="primary" link icon="edit" @click="openAppUpdate(row)">编辑</el-button>
              <el-button type="danger" link icon="delete" @click="removeAppUpdate(row)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
        <Pager :state="appUpdates" />
      </section>
    </template>

    <template v-else-if="pageKey === 'legalConsents'">
      <section class="work-panel">
        <div class="filter-panel compact-filter">
          <el-form :inline="true" :model="legalConsents.search">
            <el-form-item label="用户ID"><el-input-number v-model="legalConsents.search.userId" :min="0" /></el-form-item>
            <el-form-item label="文档ID"><el-input-number v-model="legalConsents.search.documentId" :min="0" /></el-form-item>
            <el-form-item label="类型"><el-input v-model="legalConsents.search.documentType" clearable /></el-form-item>
            <el-form-item label="平台"><el-input v-model="legalConsents.search.platform" clearable /></el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(legalConsents)">查询</el-button>
              <el-button icon="refresh" @click="reset(legalConsents)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <RemoteTable :state="legalConsents" :columns="legalConsentColumns">
          <template #operate="{ row }">
            <el-button type="danger" link icon="delete" @click="removeLegalConsent(row)">删除</el-button>
          </template>
        </RemoteTable>
      </section>
    </template>

    <template v-else>
      <section class="work-panel">
        <div class="log-toolbar">
          <el-radio-group v-model="logTab" @change="loadActiveLog">
            <el-radio-button label="connections">连接日志</el-radio-button>
            <el-radio-button label="codeAttempts">设备码日志</el-radio-button>
            <el-radio-button label="deletions">注销记录</el-radio-button>
          </el-radio-group>
        </div>
        <div v-if="logTab === 'connections'" class="filter-panel compact-filter">
          <el-form :inline="true" :model="connections.search">
            <el-form-item label="发起用户"><el-input-number v-model="connections.search.fromUserId" :min="0" /></el-form-item>
            <el-form-item label="状态"><el-input v-model="connections.search.status" clearable /></el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(connections)">查询</el-button>
              <el-button icon="refresh" @click="reset(connections)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <div v-else-if="logTab === 'codeAttempts'" class="filter-panel compact-filter">
          <el-form :inline="true" :model="codeAttempts.search">
            <el-form-item label="用户ID"><el-input-number v-model="codeAttempts.search.fromUserId" :min="0" /></el-form-item>
            <el-form-item label="状态"><el-input v-model="codeAttempts.search.status" clearable /></el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(codeAttempts)">查询</el-button>
              <el-button icon="refresh" @click="reset(codeAttempts)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <div v-else class="filter-panel compact-filter">
          <el-form :inline="true" :model="deletions.search">
            <el-form-item label="用户ID"><el-input-number v-model="deletions.search.userId" :min="0" /></el-form-item>
            <el-form-item label="脱敏邮箱"><el-input v-model="deletions.search.emailMasked" clearable placeholder="例如 a***e@example.com" /></el-form-item>
            <el-form-item label="触发方">
              <el-select v-model="deletions.search.operator" clearable placeholder="全部">
                <el-option label="用户自助" value="self" />
                <el-option label="后台处理" value="admin" />
              </el-select>
            </el-form-item>
            <el-form-item>
              <el-button type="primary" icon="search" @click="reload(deletions)">查询</el-button>
              <el-button icon="refresh" @click="reset(deletions)">重置</el-button>
            </el-form-item>
          </el-form>
        </div>
        <RemoteTable v-if="logTab === 'connections'" :state="connections" :columns="connectionColumns">
          <template #operate="{ row }">
            <el-button type="danger" link icon="delete" @click="removeConnection(row)">删除</el-button>
          </template>
        </RemoteTable>
        <RemoteTable v-else-if="logTab === 'codeAttempts'" :state="codeAttempts" :columns="codeAttemptColumns">
          <template #operate="{ row }">
            <el-button type="danger" link icon="delete" @click="removeCodeAttempt(row)">删除</el-button>
          </template>
        </RemoteTable>
        <RemoteTable v-else :state="deletions" :columns="deletionColumns">
          <template #operate="{ row }">
            <el-button type="primary" link icon="view" @click="openDeletion(row)">详情</el-button>
          </template>
        </RemoteTable>
      </section>
    </template>

    <el-drawer v-model="userDrawer" size="42%" :show-close="false">
      <template #header>
        <div class="drawer-header">
          <span>{{ userForm.id ? '编辑远程用户' : '新增远程用户' }}</span>
          <div>
            <el-button @click="userDrawer = false">取消</el-button>
            <el-button type="primary" :loading="savingUser" @click="submitUser">保存</el-button>
          </div>
        </div>
      </template>
      <el-form ref="userFormRef" label-width="96px" :model="userForm" :rules="userRules">
        <el-form-item label="邮箱" prop="email"><el-input v-model="userForm.email" placeholder="登录邮箱" /></el-form-item>
        <el-form-item label="状态" prop="status">
          <el-select v-model="userForm.status">
            <el-option label="正常" value="active" />
            <el-option label="禁用" value="disabled" />
          </el-select>
        </el-form-item>
        <el-form-item :label="userForm.id ? '新密码' : '初始密码'" prop="password">
          <el-input v-model="userForm.password" show-password :placeholder="userForm.id ? '留空则不修改密码' : '至少 6 位'" />
        </el-form-item>
      </el-form>
    </el-drawer>

    <el-drawer v-model="legalDocumentDrawer" size="55%" :show-close="false">
      <template #header>
        <div class="drawer-header">
          <span>{{ legalDocumentForm.id ? '编辑协议文档' : '新增协议文档' }}</span>
          <div>
            <el-button @click="legalDocumentDrawer = false">取消</el-button>
            <el-button type="primary" :loading="savingLegalDocument" @click="submitLegalDocument">保存</el-button>
          </div>
        </div>
      </template>
      <el-form label-width="100px" :model="legalDocumentForm">
        <el-form-item label="类型">
          <el-select v-model="legalDocumentForm.type">
            <el-option label="隐私政策" value="privacy_policy" />
            <el-option label="用户协议" value="user_agreement" />
          </el-select>
        </el-form-item>
        <el-form-item label="平台">
          <el-select v-model="legalDocumentForm.platform">
            <el-option label="全部平台" value="all" />
            <el-option label="iOS" value="ios" />
            <el-option label="macOS" value="macos" />
            <el-option label="Windows" value="windows" />
          </el-select>
        </el-form-item>
        <el-form-item label="版本"><el-input v-model="legalDocumentForm.version" placeholder="例如 2026.05.19" /></el-form-item>
        <el-form-item label="标题"><el-input v-model="legalDocumentForm.title" /></el-form-item>
        <el-form-item label="格式">
          <el-select v-model="legalDocumentForm.contentFormat">
            <el-option label="markdown" value="markdown" />
            <el-option label="html" value="html" />
          </el-select>
        </el-form-item>
        <el-form-item label="发布"><el-switch v-model="legalDocumentForm.published" /></el-form-item>
        <el-form-item label="内容"><el-input v-model="legalDocumentForm.content" type="textarea" :rows="16" /></el-form-item>
      </el-form>
    </el-drawer>

    <el-drawer v-model="appUpdateDrawer" size="55%" :show-close="false">
      <template #header>
        <div class="drawer-header">
          <span>{{ appUpdateForm.id ? '编辑在线更新版本' : '新增在线更新版本' }}</span>
          <div>
            <el-button @click="appUpdateDrawer = false">取消</el-button>
            <el-button type="primary" :loading="savingAppUpdate" @click="submitAppUpdate">保存</el-button>
          </div>
        </div>
      </template>
      <el-form label-width="112px" :model="appUpdateForm">
        <el-form-item label="平台">
          <el-select v-model="appUpdateForm.platform" @change="syncUpdateTypeForPlatform">
            <el-option label="Android" value="android" />
            <el-option label="Windows" value="windows" />
            <el-option label="macOS" value="macos" />
            <el-option label="iOS" value="ios" />
            <el-option label="全平台兜底" value="all" />
          </el-select>
        </el-form-item>
        <el-form-item label="通道">
          <el-select v-model="appUpdateForm.channel">
            <el-option label="stable" value="stable" />
            <el-option label="beta" value="beta" />
          </el-select>
        </el-form-item>
        <el-form-item label="版本号"><el-input v-model="appUpdateForm.version" placeholder="例如 1.2.0" /></el-form-item>
        <el-form-item label="构建号"><el-input v-model="appUpdateForm.buildNumber" clearable placeholder="例如 120" /></el-form-item>
        <el-form-item label="架构">
          <el-select v-model="appUpdateForm.packageArch">
            <el-option label="Universal" value="universal" />
            <el-option label="Apple Silicon" value="arm64" />
            <el-option label="Intel" value="x86_64" />
          </el-select>
        </el-form-item>
        <el-form-item label="最低版本"><el-input v-model="appUpdateForm.minimumVersion" clearable placeholder="低于该版本强制更新" /></el-form-item>
        <el-form-item label="更新方式">
          <el-select v-model="appUpdateForm.updateType">
            <el-option label="下载链接" value="link" />
            <el-option label="上传文件" value="file" />
            <el-option label="App Store" value="app_store" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="appUpdateForm.platform === 'macos'" label="DMG 文件">
          <div class="upload-row">
            <el-upload :show-file-list="false" :http-request="uploadAppUpdatePackage" accept=".dmg">
              <el-button icon="upload" :loading="uploadingAppPackage">上传 DMG</el-button>
            </el-upload>
            <span>{{ appUpdateForm.packageFileName || '未上传文件' }}</span>
          </div>
        </el-form-item>
        <el-form-item label="下载链接"><el-input v-model="appUpdateForm.downloadUrl" clearable placeholder="Android / Windows 下载页，macOS DMG URL" /></el-form-item>
        <el-form-item v-if="appUpdateForm.platform === 'ios'" label="商店链接"><el-input v-model="appUpdateForm.appStoreUrl" clearable placeholder="App Store URL" /></el-form-item>
        <el-form-item label="SHA256"><el-input v-model="appUpdateForm.packageSha256" clearable placeholder="可选，安装包校验值" /></el-form-item>
        <el-form-item label="更新说明"><el-input v-model="appUpdateForm.releaseNotes" type="textarea" :rows="6" /></el-form-item>
        <el-form-item label="强制更新"><el-switch v-model="appUpdateForm.forceUpdate" /></el-form-item>
        <el-form-item label="发布"><el-switch v-model="appUpdateForm.published" /></el-form-item>
      </el-form>
    </el-drawer>

    <el-drawer v-model="deletionDrawer" size="52%" :show-close="false">
      <template #header>
        <div class="drawer-header">
          <span>注销记录详情</span>
          <el-button @click="deletionDrawer = false">关闭</el-button>
        </div>
      </template>
      <div v-if="selectedDeletion" class="deletion-detail">
        <div class="user-summary">
          <div><span>用户ID</span><strong>{{ selectedDeletion.userId }}</strong></div>
          <div><span>脱敏邮箱</span><strong>{{ selectedDeletion.emailMasked || '-' }}</strong></div>
          <div><span>注销时间</span><strong>{{ selectedDeletion.deletedAtSnapshot || selectedDeletion.CreatedAt || '-' }}</strong></div>
          <div><span>注销原因</span><strong>{{ selectedDeletion.reason || '-' }}</strong></div>
        </div>
        <h4>服务权益快照</h4>
        <pre>{{ formatSnapshot(selectedDeletion.subscriptionSnapshot) }}</pre>
        <h4>服务开通记录快照</h4>
        <pre>{{ formatSnapshot(selectedDeletion.orderSnapshot) }}</pre>
        <h4>设备快照</h4>
        <pre>{{ formatSnapshot(selectedDeletion.deviceSnapshot) }}</pre>
        <h4>权益用量快照</h4>
        <pre>{{ formatSnapshot(selectedDeletion.usageSnapshot) }}</pre>
      </div>
    </el-drawer>
  </div>
</template>

<script setup>
import { computed, h, onMounted, reactive, ref, resolveComponent, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  banRemoteUser,
  deleteRemoteAppUpdate,
  deleteRemoteCodeAttempt,
  deleteRemoteConnection,
  deleteRemoteDevice,
  deleteRemoteLegalConsent,
  deleteRemoteLegalDocument,
  deleteRemoteUser,
  getRemoteAppFooter,
  kickRemoteUser,
  listRemoteAppUpdates,
  listRemoteAccountDeletions,
  listRemoteCodeAttempts,
  listRemoteConnections,
  listRemoteDevices,
  listRemoteLegalConsents,
  listRemoteLegalDocuments,
  listRemoteUsers,
  saveRemoteAppFooter,
  saveRemoteAppUpdate,
  saveRemoteLegalDocument,
  saveRemoteUser,
  kickRemoteDevice,
  updateRemoteDevice,
  updateRemoteUserStatus
} from '@/api/remoteAdmin'
import { uploadFile } from '@/api/fileUploadAndDownload'

const ElPagination = resolveComponent('el-pagination')
const ElTable = resolveComponent('el-table')
const ElTableColumn = resolveComponent('el-table-column')
const route = useRoute()

const logTab = ref('connections')
const selectedUser = ref(null)
const userDrawer = ref(false)
const savingUser = ref(false)
const userFormRef = ref(null)

const routePageMap = {
  remoteAdmin: 'users',
  remoteUsers: 'users',
  remoteDevices: 'devices',
  remoteConnections: 'connections',
  remoteCodeAttempts: 'codeAttempts',
  remoteAccountDeletions: 'accountDeletions',
  remoteLegal: 'legalDocuments',
  remoteLegalDocuments: 'legalDocuments',
  remoteAppFooter: 'appFooter',
  remoteAppUpdates: 'appUpdates',
  remoteLegalConsents: 'legalConsents'
}
const pageKey = computed(() => routePageMap[route.name] || 'users')
const pageMeta = computed(() => ({
  users: { title: '用户列表', description: '按用户组织账号、设备和会话控制。' },
  devices: { title: '设备管理', description: '查看设备在线状态，调整远程开关、连接策略和设备状态。' },
  connections: { title: '连接日志', description: '查看远程连接请求、传输方式和拒绝原因。' },
  codeAttempts: { title: '设备码日志', description: '追踪设备码解析尝试、失败原因和来源用户。' },
  accountDeletions: { title: '注销记录', description: '查看账号注销快照、原因和处理来源。' },
  legalDocuments: { title: '协议文档', description: '维护隐私政策、用户协议等客户端协议版本。' },
  appFooter: { title: '页脚配置', description: '维护登录页、注册页和设置页底部版权与备案文案。' },
  appUpdates: { title: '在线更新', description: '配置 Android、Windows、macOS 和 iOS 的版本提示、下载链接和安装包。' },
  legalConsents: { title: '协议同意记录', description: '查看用户对协议版本的确认记录。' },
  logs: { title: '日志', description: '查看连接请求、设备码解析和注销记录。' }
}[pageKey.value]))

const createState = (loader, search = {}) => reactive({ loader, search, initialSearch: { ...search }, list: [], total: 0, page: 1, pageSize: 10, loaded: false })
const users = createState(listRemoteUsers, { email: '', status: '' })
const devices = createState(listRemoteDevices, { userId: 0, deviceName: '', deviceType: '', status: '' })
const connections = createState(listRemoteConnections, { fromUserId: 0, toUserId: 0, toDeviceId: 0, status: '', transport: '' })
const codeAttempts = createState(listRemoteCodeAttempts, { targetDeviceId: 0, fromUserId: 0, status: '' })
const deletions = createState(listRemoteAccountDeletions, { userId: 0, emailMasked: '', emailHash: '', operator: '' })
const legalDocuments = createState(listRemoteLegalDocuments, { type: '', platform: '', published: null })
const appUpdates = createState(listRemoteAppUpdates, { platform: '', channel: '', packageArch: '', published: null })
const legalConsents = createState(listRemoteLegalConsents, { userId: 0, documentId: 0, documentType: '', platform: '' })

const load = async (state, force = false) => {
  if (!force && state.loaded) return
  const res = await state.loader({ ...state.search, page: state.page, pageSize: state.pageSize })
  state.list = res.data.list || []
  state.total = res.data.total || 0
  state.loaded = true
}
const reload = (state) => { state.page = 1; state.loaded = false; return load(state, true) }
const reset = (state) => { Object.assign(state.search, state.initialSearch); return reload(state) }

const loadUserSide = async (userId) => {
  devices.search.userId = userId
  await reload(devices)
}
const selectUser = (row) => {
  if (!row) return
  selectedUser.value = row
  loadUserSide(row.id)
}

const loadCurrentPage = async () => {
  if (pageKey.value === 'users') {
    await load(users)
    if (!selectedUser.value && users.list.length) selectUser(users.list[0])
    return
  }
  if (pageKey.value === 'devices') return load(devices)
  if (pageKey.value === 'connections') return load(connections)
  if (pageKey.value === 'codeAttempts') return load(codeAttempts)
  if (pageKey.value === 'accountDeletions') return load(deletions)
  if (pageKey.value === 'legalDocuments') return load(legalDocuments)
  if (pageKey.value === 'appFooter') return loadAppFooter()
  if (pageKey.value === 'appUpdates') return load(appUpdates)
  if (pageKey.value === 'legalConsents') return load(legalConsents)
  return loadActiveLog()
}
const loadActiveLog = () => load(logTab.value === 'connections' ? connections : logTab.value === 'codeAttempts' ? codeAttempts : deletions)

const Pager = (props) => h('div', { class: 'list-pager' }, [h(ElPagination, {
  currentPage: props.state.page,
  pageSize: props.state.pageSize,
  pageSizes: [10, 30, 50, 100],
  total: props.state.total,
  layout: 'total, sizes, prev, pager, next, jumper',
  'onUpdate:currentPage': (value) => { props.state.page = value; load(props.state, true) },
  'onUpdate:pageSize': (value) => { props.state.pageSize = value; props.state.page = 1; load(props.state, true) }
})])
Pager.props = ['state']

const RemoteTable = (props, { slots }) => h('div', [
  h(ElTable, { data: props.state.list }, () => [
    ...props.columns.map((col) => h(ElTableColumn, { prop: col.prop, label: col.label, width: col.width, minWidth: col.minWidth })),
    slots.operate ? h(ElTableColumn, { label: '操作', fixed: 'right', width: 150 }, { default: ({ row }) => slots.operate({ row }) }) : null
  ]),
  h(Pager, { state: props.state })
])
RemoteTable.props = ['state', 'columns']

const connectionColumns = [{ prop: 'connectionId', label: '连接ID', width: 120 }, { prop: 'fromUserId', label: '发起用户', width: 100 }, { prop: 'fromDeviceId', label: '发起设备', width: 100 }, { prop: 'toUserId', label: '目标用户', width: 100 }, { prop: 'toDeviceId', label: '目标设备', width: 100 }, { prop: 'status', label: '状态', width: 120 }, { prop: 'transport', label: '传输', width: 100 }, { prop: 'firstPacketLatencyMs', label: '首包(ms)', width: 110 }, { prop: 'reason', label: '原因', minWidth: 160 }, { prop: 'CreatedAt', label: '创建时间', minWidth: 180 }]
const codeAttemptColumns = [{ prop: 'id', label: 'ID', width: 80 }, { prop: 'targetDeviceId', label: '目标设备', width: 100 }, { prop: 'fromUserId', label: '发起用户', width: 100 }, { prop: 'codeHashPrefix', label: 'Hash前缀', minWidth: 140 }, { prop: 'status', label: '状态', width: 120 }, { prop: 'failureReason', label: '失败原因', minWidth: 150 }, { prop: 'CreatedAt', label: '创建时间', minWidth: 180 }]
const deletionColumns = [{ prop: 'id', label: 'ID', width: 80 }, { prop: 'userId', label: '用户ID', width: 100 }, { prop: 'emailMasked', label: '脱敏邮箱', minWidth: 180 }, { prop: 'statusSnapshot', label: '注销前状态', width: 120 }, { prop: 'operator', label: '触发方', width: 100 }, { prop: 'reason', label: '原因', minWidth: 160 }, { prop: 'deletedAtSnapshot', label: '注销时间', minWidth: 180 }]
const legalDocumentColumns = [{ prop: 'id', label: 'ID', width: 80 }, { prop: 'type', label: '类型', minWidth: 160 }, { prop: 'platform', label: '平台', width: 100 }, { prop: 'version', label: '版本', width: 130 }, { prop: 'title', label: '标题', minWidth: 180 }, { prop: 'contentFormat', label: '格式', width: 100 }, { prop: 'published', label: '发布', width: 90 }, { prop: 'effectiveAt', label: '生效时间', minWidth: 180 }]
const legalConsentColumns = [{ prop: 'id', label: 'ID', width: 80 }, { prop: 'userId', label: '用户ID', width: 100 }, { prop: 'documentId', label: '文档ID', width: 100 }, { prop: 'documentType', label: '类型', minWidth: 160 }, { prop: 'documentVersion', label: '版本', width: 130 }, { prop: 'platform', label: '平台', width: 100 }, { prop: 'consentedAt', label: '同意时间', minWidth: 180 }]

const statusText = (status) => ({ active: '正常', disabled: '禁用' }[status] || status || '-')

const userForm = reactive({ id: 0, email: '', status: 'active', password: '' })
const userRules = {
  email: [{ required: true, message: '请输入邮箱', trigger: 'blur' }, { type: 'email', message: '邮箱格式不正确', trigger: 'blur' }],
  status: [{ required: true, message: '请选择状态', trigger: 'change' }],
  password: [{ min: 6, message: '密码至少 6 位', trigger: 'blur' }]
}
const openUser = (row = {}) => {
  Object.assign(userForm, { id: 0, email: '', status: 'active', password: '' }, row, { password: '' })
  userDrawer.value = true
}
const submitUser = async () => {
  const valid = await userFormRef.value?.validate().catch(() => false)
  if (!valid) return
  if (!userForm.id && !userForm.password) {
    ElMessage.warning('新增远程用户必须设置初始密码')
    return
  }
  savingUser.value = true
  try {
    await saveRemoteUser(userForm)
    userDrawer.value = false
    await reload(users)
    ElMessage.success('保存成功')
  } finally {
    savingUser.value = false
  }
}
const updateUserStatus = async (row) => { await updateRemoteUserStatus({ id: row.id, status: row.status }); ElMessage.success('更新成功') }
const kick = async (row) => { await kickRemoteUser({ id: row.id }); ElMessage.success(`已踢下线用户 ${row.id}`) }
const ban = async (row) => {
  await ElMessageBox.confirm(`确认封禁用户 ${row.id} 并撤销刷新令牌？`, '确认操作', { type: 'warning' })
  await banRemoteUser({ id: row.id })
  ElMessage.success('已封禁')
  reload(users)
}
const removeUser = async (row) => {
  const label = row.email || `ID ${row.id}`
  await ElMessageBox.confirm(
    `确认删除远程用户 ${label}？这会删除该用户的令牌、设备、授权、连接和协议同意记录，并保留一条后台注销快照。`,
    '删除远程用户',
    { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' }
  )
  await deleteRemoteUser({ id: row.id })
  if (selectedUser.value?.id === row.id) selectedUser.value = null
  await reload(users)
  if (devices.search.userId === row.id) await reload(devices)
  ElMessage.success('已删除')
}
const updateDevice = async (row) => { await updateRemoteDevice({ id: row.id, deviceName: row.deviceName, approvalPolicy: row.approvalPolicy, remoteEnabled: row.remoteEnabled, status: row.status }); ElMessage.success('更新成功') }
const kickDevice = async (row) => {
  await kickRemoteDevice({ id: row.id })
  await reload(devices)
  ElMessage.success(`已踢下线设备 ${row.id}`)
}
const removeDevice = async (row) => {
  await ElMessageBox.confirm(`确认删除设备 ${row.deviceName || row.id}？关联授权、连接和设备码记录会一起清理。`, '删除设备', { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' })
  await deleteRemoteDevice({ id: row.id })
  await reload(devices)
  ElMessage.success('已删除')
}

const removeConnection = async (row) => {
  await ElMessageBox.confirm(`确认删除连接记录 ${row.id}？`, '删除连接记录', { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' })
  await deleteRemoteConnection({ id: row.id })
  await reload(connections)
  ElMessage.success('已删除')
}
const removeCodeAttempt = async (row) => {
  await ElMessageBox.confirm(`确认删除设备码日志 ${row.id}？`, '删除设备码日志', { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' })
  await deleteRemoteCodeAttempt({ id: row.id })
  await reload(codeAttempts)
  ElMessage.success('已删除')
}

const deletionDrawer = ref(false)
const selectedDeletion = ref(null)
const openDeletion = (row) => {
  selectedDeletion.value = row
  deletionDrawer.value = true
}
const formatSnapshot = (value) => JSON.stringify(value || {}, null, 2)

const legalDocumentDrawer = ref(false)
const savingLegalDocument = ref(false)
const legalDocumentForm = reactive({ id: 0, type: 'privacy_policy', platform: 'all', version: '', title: '', contentFormat: 'markdown', content: '', published: false })
const openLegalDocument = (row = {}) => {
  Object.assign(legalDocumentForm, { id: 0, type: 'privacy_policy', platform: 'all', version: '', title: '', contentFormat: 'markdown', content: '', published: false }, row)
  legalDocumentDrawer.value = true
}
const submitLegalDocument = async () => {
  savingLegalDocument.value = true
  try {
    await saveRemoteLegalDocument(legalDocumentForm)
    legalDocumentDrawer.value = false
    await reload(legalDocuments)
    ElMessage.success('保存成功')
  } finally {
    savingLegalDocument.value = false
  }
}
const removeLegalDocument = async (row) => {
  const publishedWarning = row.published ? '当前文档处于发布状态，删除前请确认已有替代版本。' : ''
  await ElMessageBox.confirm(`确认删除协议文档 ${row.title || row.id}？${publishedWarning}`, '删除协议文档', { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' })
  await deleteRemoteLegalDocument({ id: row.id })
  await reload(legalDocuments)
  ElMessage.success('已删除')
}

const savingAppFooter = ref(false)
const appFooterForm = reactive({
  id: 0,
  platform: 'ios',
  companyName: '禾屿科技',
  copyrightText: '© 2026 禾屿科技',
  icpText: 'ICP备案信息待更新',
  recordText: '',
  supportUrl: '',
  privacyUrl: '',
  published: true
})
const loadAppFooter = async () => {
  const res = await getRemoteAppFooter({ platform: appFooterForm.platform || 'ios' })
  Object.assign(appFooterForm, {
    id: 0,
    platform: appFooterForm.platform || 'ios',
    companyName: '禾屿科技',
    copyrightText: '© 2026 禾屿科技',
    icpText: 'ICP备案信息待更新',
    recordText: '',
    supportUrl: '',
    privacyUrl: '',
    published: true
  }, res.data || {})
}
const submitAppFooter = async () => {
  savingAppFooter.value = true
  try {
    await saveRemoteAppFooter(appFooterForm)
    await loadAppFooter()
    ElMessage.success('保存成功')
  } finally {
    savingAppFooter.value = false
  }
}

const appUpdateDrawer = ref(false)
const savingAppUpdate = ref(false)
const uploadingAppPackage = ref(false)
const defaultAppUpdateForm = () => ({
  id: 0,
  platform: 'macos',
  channel: 'stable',
  packageArch: 'universal',
  version: '',
  buildNumber: '',
  minimumVersion: '',
  releaseNotes: '',
  updateType: 'file',
  downloadUrl: '',
  appStoreUrl: '',
  packageFileId: null,
  packageFileName: '',
  packageFileSize: 0,
  packageSha256: '',
  forceUpdate: false,
  published: false
})
const appUpdateForm = reactive(defaultAppUpdateForm())
const syncUpdateTypeForPlatform = () => {
  if (appUpdateForm.platform === 'macos') appUpdateForm.updateType = 'file'
  else if (appUpdateForm.platform === 'ios') appUpdateForm.updateType = 'app_store'
  else appUpdateForm.updateType = 'link'
}
const openAppUpdate = (row = {}) => {
  Object.assign(appUpdateForm, defaultAppUpdateForm(), row)
  syncUpdateTypeForPlatform()
  appUpdateDrawer.value = true
}
const uploadAppUpdatePackage = async ({ file }) => {
  if (!file?.name?.toLowerCase().endsWith('.dmg')) {
    ElMessage.warning('请上传 DMG 文件')
    return
  }
  uploadingAppPackage.value = true
  try {
    const form = new FormData()
    form.append('file', file)
    form.append('classId', '0')
    const res = await uploadFile(form, { noSave: 1 })
    const data = res.data?.file || res.data || {}
    appUpdateForm.downloadUrl = data.url || data.Url || appUpdateForm.downloadUrl
    appUpdateForm.packageFileId = data.id || null
    appUpdateForm.packageFileName = data.name || file.name
    appUpdateForm.packageFileSize = data.size || file.size || 0
    appUpdateForm.updateType = 'file'
    ElMessage.success('上传成功')
  } finally {
    uploadingAppPackage.value = false
  }
}
const submitAppUpdate = async () => {
  savingAppUpdate.value = true
  try {
    await saveRemoteAppUpdate(appUpdateForm)
    appUpdateDrawer.value = false
    await reload(appUpdates)
    ElMessage.success('保存成功')
  } finally {
    savingAppUpdate.value = false
  }
}
const removeAppUpdate = async (row) => {
  await ElMessageBox.confirm(`确认删除 ${row.platform} ${row.version} 版本记录？`, '删除版本记录', { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' })
  await deleteRemoteAppUpdate({ id: row.id })
  await reload(appUpdates)
  ElMessage.success('已删除')
}

const removeLegalConsent = async (row) => {
  await ElMessageBox.confirm(`确认删除协议同意记录 ${row.id}？`, '删除协议同意记录', { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' })
  await deleteRemoteLegalConsent({ id: row.id })
  await reload(legalConsents)
  ElMessage.success('已删除')
}

watch(() => route.name, loadCurrentPage)
onMounted(loadCurrentPage)
</script>

<style scoped>
.remote-page { display: flex; flex-direction: column; gap: 16px; }
.page-heading { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; padding: 2px 2px 0; }
.page-kicker { display: block; color: #64748b; font-size: 12px; font-weight: 650; margin-bottom: 4px; }
.page-heading h2 { margin: 0; color: #111827; font-size: 22px; font-weight: 700; letter-spacing: 0; }
.page-heading p { margin: 6px 0 0; color: #64748b; font-size: 13px; }
.page-actions { display: flex; align-items: center; gap: 8px; }
.section-grid { display: grid; gap: 16px; align-items: start; }
.user-layout { grid-template-columns: minmax(0, 1.45fr) minmax(420px, .9fr); }
.footer-layout { grid-template-columns: minmax(0, 1.2fr) minmax(360px, .75fr); }
.work-panel { min-width: 0; border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; background: #fff; }
.user-side { position: sticky; top: 12px; }
.panel-title { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; margin-bottom: 14px; }
.panel-title h3 { margin: 0 0 4px; font-size: 16px; font-weight: 650; color: #111827; }
.panel-title span { color: #6b7280; font-size: 13px; }
.compact-filter { margin-bottom: 16px; box-shadow: none !important; border: 1px solid #e5e7eb !important; border-radius: 8px !important; }
.identity-cell { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
.identity-cell strong { color: #111827; font-weight: 650; word-break: break-all; }
.identity-cell span { color: #64748b; font-size: 12px; word-break: break-all; }
.log-toolbar { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; }
.user-summary { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 18px; }
.user-summary div { border: 1px solid #e5e7eb; border-radius: 8px; padding: 12px; }
.user-summary span { display: block; color: #6b7280; font-size: 12px; margin-bottom: 6px; }
.user-summary strong { color: #111827; font-weight: 650; word-break: break-all; }
.detail-block { margin-top: 18px; }
.detail-heading { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 10px; }
.detail-heading h4 { margin: 0; color: #111827; font-size: 14px; font-weight: 650; }
.current-plan { border-top: 1px solid #eef2f7; padding-top: 16px; }
.plan-summary { display: grid; grid-template-columns: 1fr 110px 1fr auto; gap: 10px; align-items: center; border: 1px solid #e5e7eb; border-radius: 8px; padding: 12px; }
.plan-summary span { display: block; color: #6b7280; font-size: 12px; margin-bottom: 4px; }
.plan-summary strong { color: #111827; font-weight: 650; word-break: break-all; }
.drawer-header { display: flex; align-items: center; justify-content: space-between; width: 100%; font-size: 18px; }
.deletion-detail { display: flex; flex-direction: column; gap: 14px; }
.deletion-detail h4 { margin: 0; color: #111827; font-size: 14px; font-weight: 650; }
.deletion-detail pre { margin: 0; padding: 12px; border: 1px solid #e5e7eb; border-radius: 8px; background: #f8fafc; color: #334155; white-space: pre-wrap; word-break: break-word; font-size: 12px; line-height: 1.55; }
.footer-preview { position: sticky; top: 12px; }
.footer-lines { display: flex; flex-direction: column; gap: 8px; align-items: center; padding: 28px 14px; border: 1px solid #e5e7eb; border-radius: 8px; background: #f8fafc; color: #64748b; text-align: center; font-size: 13px; line-height: 1.45; }
.footer-lines strong { color: #111827; font-size: 14px; font-weight: 650; }
.upload-row { display: flex; align-items: center; gap: 12px; color: #64748b; font-size: 13px; min-width: 0; }
.upload-row span { word-break: break-all; }
@media (max-width: 1280px) { .user-layout, .footer-layout { grid-template-columns: 1fr; } .user-side, .footer-preview { position: static; } }
@media (max-width: 768px) { .page-heading { align-items: flex-start; flex-direction: column; } .plan-summary, .user-summary { grid-template-columns: 1fr; } }
</style>

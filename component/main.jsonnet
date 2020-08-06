local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_cloudscale;

local cloudscale_api_token = inv.parameters.csi_cloudscale.api_token;

// StorageClasses
local provisioner = { provisioner: 'ch.cloudscale.csi' };

local storageclass_ssd = sc.storageClass('ssd') {
  parameters: {
    'csi.cloudscale.ch/volume-type': 'ssd',
  },
};

local storageclass_bulk = sc.storageClass('bulk') {
  parameters: {
    'csi.cloudscale.ch/volume-type': 'bulk',
  },
};

local storageclass_ssd_luks = sc.storageClass('ssd-encrypted') {
  parameters+: {
    'csi.cloudscale.ch/volume-type': 'ssd',
    'csi.cloudscale.ch/luks-encrypted': 'true',
    'csi.cloudscale.ch/luks-cipher': 'aes-xts-plain64',
    'csi.cloudscale.ch/luks-key-size': '512',
    'csi.storage.k8s.io/node-stage-secret-namespace': '${pvc.namespace}',
    'csi.storage.k8s.io/node-stage-secret-name': '${pvc.name}-luks-key',
  },
};

local storageclass_bulk_luks = sc.storageClass('bulk-encrypted') {
  parameters+: {
    'csi.cloudscale.ch/volume-type': 'bulk',
    'csi.cloudscale.ch/luks-encrypted': 'true',
    'csi.cloudscale.ch/luks-cipher': 'aes-xts-plain64',
    'csi.cloudscale.ch/luks-key-size': '512',
    'csi.storage.k8s.io/node-stage-secret-namespace': '${pvc.namespace}',
    'csi.storage.k8s.io/node-stage-secret-name': '${pvc.name}-luks-key',
  },
};

local secret = kube.Secret('cloudscale') {
  metadata+: {
    namespace: params.namespace,
  },
  stringData: {
    'access-token': cloudscale_api_token,
  },
};

local manifests = std.parseJson(
  kap.yaml_load_stream('csi-cloudscale/manifests/' + params.version + '/deploy.yaml')
);

{
  '01_storageclasses': [storageClass + provisioner for storageClass in [
    storageclass_ssd,
    storageclass_bulk,
    storageclass_ssd_luks,
    storageclass_bulk_luks,
  ]],
  '02_secret': secret,
  '10_deployments': [
    object {
      metadata+: {
        namespace: params.namespace,
      },
    }
    for object in manifests
    if std.setMember(object.kind, std.set(['StatefulSet', 'ServiceAccount', 'DaemonSet']))
  ],
  '20_rbac': [
    if std.objectHas(object, 'subjects') then object {
      subjects: [
        sub {
          namespace: params.namespace,
        }
        for sub in object.subjects
      ],
    }
    else object
    for object in manifests
    if std.setMember(object.kind, std.set(['ClusterRole', 'ClusterRoleBinding']))
  ],
}

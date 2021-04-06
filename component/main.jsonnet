local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_cloudscale;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local config = {
  allowVolumeExpansion: true,
  provisioner: 'ch.cloudscale.csi',
};

local storageclasses = [ [
  sc.storageClass(type) {
    parameters: {
      'csi.cloudscale.ch/volume-type': type,
    },
  } + config,
  sc.storageClass(type + '-encrypted') {
    parameters+: {
      'csi.cloudscale.ch/volume-type': type,
      'csi.cloudscale.ch/luks-encrypted': 'true',
      'csi.cloudscale.ch/luks-cipher': 'aes-xts-plain64',
      'csi.cloudscale.ch/luks-key-size': '512',
      'csi.storage.k8s.io/node-stage-secret-namespace': '${pvc.namespace}',
      'csi.storage.k8s.io/node-stage-secret-name': '${pvc.name}-luks-key',
    },
  } + config,
] for type in [ 'ssd', 'bulk' ] ];

local secret = kube.Secret('cloudscale') {
  metadata+: {
    namespace: params.namespace,
  },
  stringData: {
    'access-token': params.api_token,
  },
};

local manifests = std.parseJson(
  kap.yaml_load_stream('csi-cloudscale/manifests/' + params.version + '/deploy.yaml')
);

local customRBAC = if isOpenshift then [
  kube.RoleBinding('csi-hostnetwork') {
    roleRef_: kube.ClusterRole('system:openshift:scc:hostnetwork'),
    subjects: [ {
      kind: 'ServiceAccount',
      name: std.filter(
        function(obj) obj.kind == 'StatefulSet', manifests
      )[0].spec.template.spec.serviceAccount,
      namespace: params.namespace,
    } ],
  },
  kube.RoleBinding('csi-privileged') {
    roleRef_: kube.ClusterRole('system:openshift:scc:privileged'),
    subjects: [ {
      kind: 'ServiceAccount',
      name: std.filter(
        function(obj) obj.kind == 'DaemonSet', manifests
      )[0].spec.template.spec.serviceAccount,
      namespace: params.namespace,
    } ],
  },
] else [];

{
  [if params.namespace != 'kube-system' then '00_namespace']: kube.Namespace(params.namespace) + if isOpenshift then {
    metadata+: {
      annotations+: {
        'openshift.io/node-selector': '',
      },
    },
  } else {},
  '01_storageclasses': std.flattenArrays(storageclasses),
  '02_secret': secret,
  '10_deployments': [
    object {
      metadata+: {
        namespace: params.namespace,
      },
    }
    for object in manifests
    if std.setMember(object.kind, std.set([ 'StatefulSet', 'ServiceAccount', 'DaemonSet' ]))
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
    if std.setMember(object.kind, std.set([ 'ClusterRole', 'ClusterRoleBinding' ]))
  ],
  [if std.length(customRBAC) > 0 then '30_custom_rbac']: customRBAC,
}

local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_cloudscale;

local isOpenshift = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);

local config = {
  allowVolumeExpansion: true,
  provisioner: 'csi.cloudscale.ch',
};

local storageclasses = [ [
  sc.storageClass(type) {
    parameters: {
      fsType: params.fs_type,
      'csi.cloudscale.ch/volume-type': type,
    },
  } + config,
  sc.storageClass(type + '-encrypted') {
    parameters+: {
      fsType: params.fs_type,
      'csi.cloudscale.ch/volume-type': type,
      'csi.cloudscale.ch/luks-encrypted': 'true',
      'csi.cloudscale.ch/luks-cipher': 'aes-xts-plain64',
      'csi.cloudscale.ch/luks-key-size': '512',
      'csi.storage.k8s.io/node-stage-secret-namespace': '${pvc.namespace}',
      'csi.storage.k8s.io/node-stage-secret-name': '${pvc.name}-luks-key',
    },
  } + config,
] for type in [ 'ssd', 'bulk' ] ];

local secret = kube.Secret(params.api_token_secret_name) {
  metadata+: {
    namespace: params.namespace,
  },
  stringData: {
    'access-token': params.api_token,
  },
};

local customRBAC = if isOpenshift then [
  kube.RoleBinding('csi-hostnetwork') {
    roleRef_: kube.ClusterRole('system:openshift:scc:hostnetwork'),
    subjects: [ {
      kind: 'ServiceAccount',
      name: params.helm_values.controller.serviceAccountName,
      namespace: params.namespace,
    } ],
  },
  kube.RoleBinding('csi-privileged') {
    roleRef_: kube.ClusterRole('system:openshift:scc:privileged'),
    subjects: [ {
      kind: 'ServiceAccount',
      name: params.helm_values.node.serviceAccountName,
      namespace: params.namespace,
    } ],
  },
] else [];

local warnDeprecatedParam(o) =
  if std.objectHas(params, 'version') then
    std.trace(
      'Component parameter `version` is removed and its value is ignored. Please use parameters `charts` and `images` to override the csi-cloudscale version.',
      o
    )
  else
    o;

{
  [if params.namespace != 'kube-system' then '00_namespace']: kube.Namespace(params.namespace) + if isOpenshift then {
    metadata+: {
      annotations+: {
        'openshift.io/node-selector': '',
      },
    },
  } else {},
  '01_storageclasses': std.flattenArrays(storageclasses),
  '02_secret': warnDeprecatedParam(secret),
  [if std.length(customRBAC) > 0 then '30_custom_rbac']: customRBAC,
}

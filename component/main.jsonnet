local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_cloudscale;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

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

local defaultResources = {
  csi_driver: {
    'csi-node-driver-registrar': {
      requests: {
        cpu: '20m',
        memory: '32Mi',
      },
      limits: {
        cpu: '100m',
        memory: '128Mi',
      },
    },
    'csi-cloudscale-plugin': {
      requests: {
        cpu: '20m',
        memory: '32Mi',
      },
      limits: {
        cpu: '100m',
        memory: '128Mi',
      },
    },
  },
  controller: {
    'csi-provisioner': {
      requests: {
        cpu: '20m',
        memory: '32Mi',
      },
      limits: {
        cpu: '100m',
        memory: '128Mi',
      },
    },
    'csi-attacher': {
      requests: {
        cpu: '20m',
        memory: '32Mi',
      },
      limits: {
        cpu: '100m',
        memory: '128Mi',
      },
    },
    'csi-resizer': {
      requests: {
        cpu: '20m',
        memory: '32Mi',
      },
      limits: {
        cpu: '100m',
        memory: '128Mi',
      },
    },
    'csi-cloudscale-plugin': {
      requests: {
        cpu: '20m',
        memory: '32Mi',
      },
      limits: {
        cpu: '100m',
        memory: '128Mi',
      },
    },
  },
};

local patch_manifest(object) =
  local tolerations = params.driver_daemonset_tolerations;
  local resources = if object.kind == 'DaemonSet' then
    defaultResources.csi_driver +
    com.makeMergeable(params.resources.csi_driver)
  else if object.kind == 'StatefulSet' then
    defaultResources.controller +
    com.makeMergeable(params.resources.controller)
  else
    null;
  assert
    resources == null
    || (
      std.length(object.spec.template.spec.containers) ==
      std.length(std.objectFields(resources))
    ) : (
      'csi-cloudscale upstream manifest "%s" changed. '
      + 'Please check the default resource requests and limits configured in the component.'
    ) % (
      object.metadata.name
    );
  if (
    object.kind == 'DaemonSet'
    && object.metadata.name == 'csi-cloudscale-node'
  ) then
    object {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                resources+: com.getValueOrDefault(resources, c.name, {}),
              }
              for c in super.containers
            ],
            tolerations+: [
              tolerations[t] {
                key: t,
              }
              for t in std.objectFields(tolerations)
            ],
          },
        },
      },
    }
  else if (
    object.kind == 'StatefulSet'
    && object.metadata.name == 'csi-cloudscale-controller'
  ) then
    object {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                resources+: com.getValueOrDefault(resources, c.name, {}),
              }
              for c in super.containers
            ],
          },
        },
      },
    }
  else
    object;

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
    patch_manifest(object) {
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

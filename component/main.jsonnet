local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_cloudscale;

local cloudscale_api_token = inv.parameters.csi_cloudscale.api_token;

# StorageClasses
local storageclass = kube.StorageClass('cloudscale-volume') {
  provisioner: "ch.cloudscale.csi",
};

local storageclass_ssd = storageclass {
  metadata+: {
    name: "fast",
  },
  parameters: {
    "csi.cloudscale.ch/volume-type": "ssd"
  }
};

local storageclass_bulk = storageclass {
  metadata+: {
    name: "bulk",
  },
  parameters: {
    "csi.cloudscale.ch/volume-type": "bulk"
  }
};

local storageclass_ssd_luks = storageclass_ssd {
  metadata+: {
    name: "fast-encrypted",
  },
  parameters+: {
    "csi.cloudscale.ch/luks-encrypted": "true",
    "csi.cloudscale.ch/luks-cipher": "aes-xts-plain64",
    "csi.cloudscale.ch/luks-key-size": "512",
    "csi.storage.k8s.io/node-stage-secret-namespace": "${pvc.namespace}",
    "csi.storage.k8s.io/node-stage-secret-name": "${pvc.name}-luks-key"
  }
};

local storageclass_bulk_luks = storageclass_bulk {
  metadata+: {
    name: "bulk-encrypted"
  },
  parameters+: {
    "csi.cloudscale.ch/luks-encrypted": "true",
    "csi.cloudscale.ch/luks-cipher": "aes-xts-plain64",
    "csi.cloudscale.ch/luks-key-size": "512",
    "csi.storage.k8s.io/node-stage-secret-namespace": "${pvc.namespace}",
    "csi.storage.k8s.io/node-stage-secret-name": "${pvc.name}-luks-key"
  }
};

local secret = kube.Secret('cloudscale') {
  metadata+: {
    namespace: params.namespace
  },
  stringData: {
    "access-token": cloudscale_api_token
  },
};

{
  "00_crds": std.parseJson(kap.yaml_load('csi-cloudscale/static/csinodeinfo-crd.yaml')),
  # TODO set storageclass_ssd_luks as default as soon as secret management is automated
  "01_storageclass": [
    storageclass_ssd {
      metadata+: {
        annotations: {
          "storageclass.kubernetes.io/is-default-class": "true"
        }
      }
    },
    storageclass_bulk,
    storageclass_ssd_luks,
    storageclass_bulk_luks
  ],
  "02a_controller_serviceaccount": std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/serviceaccount.yaml')),
  "02b_controller_clusterroles": [
    std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/clusterrole-1.yaml')),
    std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/clusterrole-2.yaml')),
    std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/clusterrole-3.yaml'))
  ],
  "02c_controller_clusterrolebindings": [
    std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/clusterrolebinding-1.yaml')),
    std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/clusterrolebinding-2.yaml')),
    std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/clusterrolebinding-3.yaml'))
  ],
  "02d_controller_statefulset": std.parseJson(kap.yaml_load('csi-cloudscale/static/controller/statefulset.yaml')),
  "03a_nodeplugin_serviceaccount": std.parseJson(kap.yaml_load('csi-cloudscale/static/nodeplugin/serviceaccount.yaml')),
  "03b_nodeplugin_clusterrole": std.parseJson(kap.yaml_load('csi-cloudscale/static/nodeplugin/clusterrole.yaml')),
  "03c_nodeplugin_clusterrolebinding": std.parseJson(kap.yaml_load('csi-cloudscale/static/nodeplugin/clusterrolebinding.yaml')),
  "03d_nodeplugin_daemonset": std.parseJson(kap.yaml_load('csi-cloudscale/static/nodeplugin/daemonset.yaml')),
  "04_secret": secret
}

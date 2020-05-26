local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_cloudscale;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('csi-cloudscale', params.namespace, secrets=true);

if params.enabled then {
  'csi-cloudscale': app,
} else {}

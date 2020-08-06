local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_cloudscale;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('csi-cloudscale', params.namespace);

{
  'csi-cloudscale': app,
}

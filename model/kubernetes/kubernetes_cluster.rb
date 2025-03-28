#  frozen_string_literal: true

require_relative "../../model"

class KubernetesCluster < Sequel::Model
  one_to_one :strand, key: :id
  many_to_one :api_server_lb, class: :LoadBalancer
  many_to_one :private_subnet
  many_to_one :project
  many_to_many :cp_vms, join_table: :kubernetes_clusters_cp_vms, class: :Vm, order: :created_at
  one_to_many :nodepools, class: :KubernetesNodepool
  one_to_many :active_billing_records, class: :BillingRecord, key: :resource_id, &:active
  many_to_one :location, key: :location_id

  dataset_module Pagination

  include ResourceMethods
  include SemaphoreMethods

  semaphore :destroy

  def validate
    super
    errors.add(:cp_node_count, "must be greater than 0") if cp_node_count <= 0
    errors.add(:version, "must be a valid Kubernetes version") unless ["v1.32", "v1.31"].include?(version)
  end

  def display_state
    return "deleting" if destroy_set? || strand.label == "destroy"
    return "running" if strand.label == "wait"
    "creating"
  end

  def display_location
    location.display_name
  end

  def path
    "/location/#{display_location}/kubernetes-cluster/#{name}"
  end

  def endpoint
    api_server_lb.hostname
  end

  def sshable
    cp_vms.first.sshable
  end

  def self.kubeconfig(vm)
    rbac_token = vm.sshable.cmd("kubectl --kubeconfig <(sudo cat /etc/kubernetes/admin.conf) -n kube-system get secret k8s-access -o jsonpath='{.data.token}' | base64 -d", log: false)
    admin_kubeconfig = vm.sshable.cmd("sudo cat /etc/kubernetes/admin.conf", log: false)
    kubeconfig = YAML.safe_load(admin_kubeconfig)
    kubeconfig["users"].each do |user|
      user["user"].delete("client-certificate-data")
      user["user"].delete("client-key-data")
      user["user"]["token"] = rbac_token
    end
    kubeconfig.to_yaml
  end

  def kubeconfig
    self.class.kubeconfig(cp_vms.first)
  end
end

# Table: kubernetes_cluster
# Columns:
#  id                           | uuid                     | PRIMARY KEY
#  name                         | text                     | NOT NULL
#  cp_node_count                | integer                  | NOT NULL
#  version                      | text                     | NOT NULL
#  created_at                   | timestamp with time zone | NOT NULL DEFAULT CURRENT_TIMESTAMP
#  project_id                   | uuid                     | NOT NULL
#  private_subnet_id            | uuid                     | NOT NULL
#  api_server_lb_id             | uuid                     |
#  target_node_size             | text                     | NOT NULL
#  target_node_storage_size_gib | bigint                   |
#  location_id                  | uuid                     | NOT NULL
# Indexes:
#  kubernetes_cluster_pkey                             | PRIMARY KEY btree (id)
#  kubernetes_cluster_project_id_location_id_name_uidx | UNIQUE btree (project_id, location_id, name)
# Foreign key constraints:
#  kubernetes_cluster_api_server_lb_id_fkey  | (api_server_lb_id) REFERENCES load_balancer(id)
#  kubernetes_cluster_location_id_fkey       | (location_id) REFERENCES location(id)
#  kubernetes_cluster_private_subnet_id_fkey | (private_subnet_id) REFERENCES private_subnet(id)
#  kubernetes_cluster_project_id_fkey        | (project_id) REFERENCES project(id)
# Referenced By:
#  kubernetes_clusters_cp_vms | kubernetes_clusters_cp_vms_kubernetes_cluster_id_fkey | (kubernetes_cluster_id) REFERENCES kubernetes_cluster(id)
#  kubernetes_nodepool        | kubernetes_nodepool_kubernetes_cluster_id_fkey        | (kubernetes_cluster_id) REFERENCES kubernetes_cluster(id)

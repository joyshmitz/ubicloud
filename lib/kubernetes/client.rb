# frozen_string_literal: true

class Kubernetes::Client
  def initialize(kubernetes_cluster, session)
    @session = session
    @kubernetes_cluster = kubernetes_cluster
    @load_balancer = LoadBalancer.where(name: kubernetes_cluster.services_load_balancer_name).first
  end

  def service_deleted?(svc)
    !!svc.dig("metadata", "deletionTimestamp")
  end

  # Returns a flat array of [port, nodePort] pairs from all services
  # Format: [[src_port_0, dst_port_0], [src_port_1, dst_port_1], ...]
  def lb_desired_ports(svc_list)
    svc_list.flat_map do |svc|
      svc.dig("spec", "ports")&.map { |port| [port["port"], port["nodePort"]] } || []
    end
  end

  def load_balancer_hostname_missing?(svc)
    svc.dig("status", "loadBalancer", "ingress")&.first&.dig("hostname").to_s.empty?
  end

  def kubectl(cmd)
    @session.exec!("sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf #{cmd}")
  end

  def set_load_balancer_hostname(svc, hostname)
    patch_data = JSON.generate({
      "status" => {
        "loadBalancer" => {
          "ingress" => [{"hostname" => hostname}]
        }
      }
    })
    kubectl("-n #{svc.dig("metadata", "namespace")} patch service #{svc.dig("metadata", "name")} --type=merge -p '#{patch_data}' --subresource=status")
  end

  def sync_kubernetes_services
    k8s_svc_raw = kubectl("get service --all-namespaces --field-selector spec.type=LoadBalancer -ojson")
    svc_list = JSON.parse(k8s_svc_raw)["items"]

    if @load_balancer.nil?
      raise "services load balancer does not exist."
    end

    extra_vms, missing_vms = @kubernetes_cluster.vm_diff_for_lb(@load_balancer)
    missing_vms.each { |missing_vm| @load_balancer.add_vm(missing_vm) }
    extra_vms.each { |extra_vm| @load_balancer.detach_vm(extra_vm) }

    extra_ports, missing_ports = @kubernetes_cluster.port_diff_for_lb(@load_balancer, lb_desired_ports(svc_list))
    extra_ports.each { |port| @load_balancer.remove_port(port) }
    missing_ports.each { |port| @load_balancer.add_port(port[0], port[1]) }

    return unless @load_balancer.strand.label == "wait"
    svc_list.each { |svc| set_load_balancer_hostname(svc, @load_balancer.hostname) }
  end

  def any_lb_services_modified?
    k8s_svc_raw = kubectl("get service --all-namespaces --field-selector spec.type=LoadBalancer -ojson")
    svc_list = JSON.parse(k8s_svc_raw)["items"]

    return true if svc_list.empty? && !@load_balancer.ports.empty?

    extra_vms, missing_vms = @kubernetes_cluster.vm_diff_for_lb(@load_balancer)
    return true unless extra_vms.empty? && missing_vms.empty?

    extra_ports, missing_ports = @kubernetes_cluster.port_diff_for_lb(@load_balancer, lb_desired_ports(svc_list))
    return true unless extra_ports.empty? && missing_ports.empty?

    svc_list.any? { |svc| load_balancer_hostname_missing?(svc) }
  end
end

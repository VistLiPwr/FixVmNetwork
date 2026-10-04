 专门解决从 **VirtualBox 导出的 OVA/OVF 虚拟机**导入到 **VMware Workstation** 后无法联网的问题。

  # 修复单个 VM
  .\fix-vm-network.ps1 -VMPath "F:\targetmachine\driftblues5"

  # 修复整个文件夹所有 VM（默认 NAT 模式）
  .\fix-vm-network.ps1 -VMPath "F:\targetmachine"

  # 桥接模式
  .\fix-vm-network.ps1 -VMPath "F:\targetmachine" -NetworkType bridged

  工作原理：
  1. 修复 VMX 配置文件（网络类型 + guestOS）
  2. 通过 WSL2 Kali + qemu-nbd 挂载 VMDK 磁盘
  3. 注入 net.ifnames=0 biosdevname=0 内核参数
  4. 统一 /etc/network/interfaces 使用 eth0 + DHCP

  现在启动 Talk 虚拟机，网卡名会固定为 eth0，无论将来迁移到 VMware/VirtualBox/Proxmox 都不会再出现拿不到 IP 的问题。
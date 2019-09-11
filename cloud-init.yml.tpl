#cloud-config
repo_update: true
repo_upgrade: all
ssh_pwauth: yes
hostname: getting-started
packages:
- cowsay
users:
- default
%{ for player in players ~}
- name: ${player.login}
  passwd: ${player.password.hash}
  lock_passwd: false
  shell: /bin/bash
%{ endfor ~}
write_files:
- path: /etc/motd
  content: |2
    Welcome
runcmd:
- chmod -x /etc/update-motd.d/*
- rm /etc/legal
- hostname getting-started
- service sshd reload

#!/bin/bash

nmcli connection add type ethernet con-name enp2s0 ifname enp2s0 ipv4.addresses 192.168.1.10/24 ipv4.method manual connection.autoconnect yes
nmcli connection up enp2s0
echo "192.168.1.10 control.lab control" >> /etc/hosts
echo "192.168.1.11 podman.lab podman" >> /etc/hosts
echo "192.168.1.12 rhel-1.lab podman" >> /etc/hosts
echo "192.168.1.13 rhel-2.lab podman" >> /etc/hosts


systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# Install collection(s)
ansible-galaxy collection install ansible.eda

tee /tmp/inventory << EOF
[nodes]
rhel-1
rhel-2

[all]
podman
rhel-1
rhel-2
control

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

EOF

tee /tmp/test.yml << EOF
---
- name: Setup podman and services
  hosts: podman
  gather_facts: true
  tasks:

  - name: put password in /tmp
    ansible.builtin.command:
      cmd: echo "task {{ lookup('ansible.builtin.env', 'admin_password') }}" >> /tmp/passwd

...
EOF

ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/test.yml


# # # creates a playbook to setup environment
tee /tmp/setup.yml << EOF
---
###
### Podman setup 
###
# - name: Setup podman and services
#   hosts: podman
#   gather_facts: no
#   #become: true
#   tasks:

#     - name: Install EPEL
#       ansible.builtin.package:
#         name: https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
#         state: present
#         disable_gpg_check: true
#       become: true

#       ## Lab Fix
#     - name: Ensure crun is updated to the latest available version
#       ansible.builtin.dnf:
#         name: crun
#         state: latest
#       become: true


#     - name: Install required packages
#       ansible.builtin.package:
#         name: "{{ item }}"
#         state: present
#       loop:
#         - git
#         - tmux
#         - python3-pip
#         - podman-compose
#         - python3-dotenv
#       become: true

#     - name: Set the default branch to aap25 for migrated repositories
#       ansible.builtin.uri:
#         url: "http://gitea:3000/api/v1/repos/student/{{ item.name }}"
#         method: PATCH
#         body_format: json
#         body:
#           default_branch: "aap25"
#         headers:
#           Content-Type: "application/json"
#         user: gitea
#         password: gitea
#         force_basic_auth: yes
#         validate_certs: no
#       loop:
#         - { name: 'eda-project' }
#         - { name: 'eda-alertmanager' }
#       delegate_to: localhost

#     - name: Clone the specific branch from the migrated repo
#       ansible.builtin.git:
#         repo: "http://gitea:3000/student/{{ item.item.name }}.git"
#         dest: "/tmp/{{ item.item.name }}"
#         version: "{{ item.branch | default('main') }}"
#         force: true
#       loop:
#         - {item: {name: 'eda-alertmanager'}, branch: 'aap25'}
#         - {item: {name: 'eda-project'}, branch: 'aap25'}

#     - name: Start node_exporter and webhook services with podman-compose
#       ansible.builtin.command:
#         cmd: podman-compose up -d
#         chdir: "/tmp/eda-alertmanager/{{ item }}"
#       loop:
#         - node_exporter
#         # - webhook

#     # - name: Wait for services to start
#     #   ansible.builtin.pause:
#     #     seconds: 15

#     - name: Start prometheus with podman-compose
#       ansible.builtin.command: 
#         cmd: podman-compose up -d
#         chdir: /tmp/eda-alertmanager/prometheus

###
### Automation Controller setup 
###
- name: Setup Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
 #   SANDBOX_ID: "{{ lookup('env', '_SANDBOX_ID') | default('SANDBOX_ID_NOT_FOUND', true) }}"
  tasks:

  - name: (EXECUTION) add rhel machine credential
    ansible.controller.credential:
      name: 'rhel credential'
      organization: Default
      credential_type: Machine
      controller_host: "https://{{ ansible_host }}"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: rhel
        password: ansible123!

  - name: (EXECUTION) add rhel inventory
    ansible.controller.inventory:
      name: "rhel inventory"
      description: "rhel servers in demo environment"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (EXECUTION) add rhel inventory
    ansible.controller.inventory:
      name: "container host inventory"
      description: "podman host in demo environment"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (EXECUTION) add RHEL hosts
    ansible.controller.host:
      name: "{{ item }}"
      description: "rhel host"
      inventory: "rhel inventory"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
    loop:
      - rhel-1
      - rhel-2

  - name: (EXECUTION) add container host
    ansible.controller.host:
      name: "{{ item }}"
      description: "podman host"
      inventory: "container host inventory"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
    loop:
      - podman

  - name: (EXECUTION) Add RHEL group
    ansible.controller.group:
      name: nodes
      description: "rhel host group"
      inventory: rhel inventory
      hosts:
        - rhel-1
        - rhel-2
      variables:
        ansible_user: rhel
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (EXECUTION) Add container host group
    ansible.controller.group:
      name: nodes
      description: "container host group"
      inventory: container host inventory
      hosts:
        - podman
      variables:
        ansible_user: rhel
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (EXECUTION) Add project
    ansible.controller.project:
      name: "eda-project"
      description: "EDA project"
      organization: "Default"
      scm_type: git
      scm_url: http://gitea:3000/student/eda-project
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (EXECUTION) Configure apply baseline job template
    ansible.controller.job_template:
      name: "Apply baseline"
      job_type: "run"
      organization: "Default"
      inventory: "rhel inventory"
      project: "eda-project"
      playbook: "playbooks/alertmanager-baseline-config.yml"
      execution_environment: "Default execution environment"
      ask_variables_on_launch: true
      ask_limit_on_launch: true
      credentials:
        - "rhel credential"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (EXECUTION) Configure redeploy prometheus job template
    ansible.controller.job_template:
      name: "Redeploy prometheus stack"
      job_type: "run"
      organization: "Default"
      inventory: "container host inventory"
      project: "eda-project"
      playbook: "playbooks/redeploy-prometheus.yml"
      execution_environment: "Default execution environment"
      ask_variables_on_launch: true
      ask_limit_on_launch: true
      credentials:
        - "rhel credential"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (EXECUTION) Configure fix storage job template
    ansible.controller.job_template:
      name: "Remediate disk space alert"
      job_type: "run"
      organization: "Default"
      inventory: "rhel inventory"
      project: "eda-project"
      playbook: "playbooks/fix-storage.yml"
      execution_environment: "Default execution environment"
      ask_variables_on_launch: true
      ask_limit_on_launch: true
      credentials:
        - "rhel credential"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  # - name: (DECISIONS) Create an AAP Credential
  #   ansible.eda.credential:
  #     name: "AAP"
  #     description: "To execute jobs from EDA"
  #     inputs:
  #       host: "https://aap.{{ SANDBOX_ID }}.instruqt.io/api/controller/"
  #       username: "admin"
  #       password: "ansible123!"
  #     credential_type_name: "Red Hat Ansible Automation Platform"
  #     organization_name: Default
  #     controller_host: https://localhost
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  # - name: (DECISIONS) Update EVENT_STREAM_BASE_URL in settings.yaml
  #   ansible.builtin.lineinfile:
  #     path: "/home/rhel/aap/eda/etc/settings.yaml"
  #     regexp: "^EVENT_STREAM_BASE_URL:.*"
  #     line: "EVENT_STREAM_BASE_URL: 'https://{{ ansible_hostname }}.{{ sandbox_id }}.instruqt.io/eda-event-streams'"
  #     backrefs: yes
  #   vars:
  #     sandbox_id: "{{ lookup('env', '_SANDBOX_ID') }}"

  - name: Create EDA Decision Environment
    ansible.eda.decision_environment:
      name: "Alertmanager DE"
      description: "Network/Kafka/Alertmanager"
      image_url: "quay.io/nmartins/network_de"
   #   credential: "Example Credential"
      organization_name: Default
      state: present
      controller_host: https://localhost
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: (DECISIONS) Restart EDA services as rhel user
    become: true
    become_user: rhel
    ansible.builtin.systemd_service:
      scope: user
      name: "{{ item }}"
      state: restarted
    loop:
      - automation-eda-activation-worker-1.service
      - automation-eda-activation-worker-2.service
      - automation-eda-api.service
      - automation-eda-daphne.service
      - automation-eda-scheduler.service
      - automation-eda-web.service
      - automation-eda-worker-1.service
      - automation-eda-worker-2.service
    register: restart_services
    until: restart_services is not failed
    retries: 5
    delay: 10


###
### RHEL nodes setup 
# ###
# - name: Setup rhel nodes
#   hosts: nodes
#   become: true
#   tasks:


#     - name: Install epel-release
#       ansible.builtin.dnf:
#         name: https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
#         state: present
#         disable_gpg_check: true

#     # - name: Install packages
#     #   ansible.builtin.dnf:
#     #     name:
#     #       - git
#     #       - podman-compose
#     #     state: present

#           ## Lab Fix
#     - name: Ensure crun is updated to the latest available version
#       ansible.builtin.dnf:
#         name: crun
#         state: latest
#       become: true

#     - name: Install required packages
#       ansible.builtin.package:
#         name: "{{ item }}"
#         state: present
#       loop:
#         - git
#         - tmux
#         - python3-pip
#         - podman-compose
#         - python3-dotenv
#       become: true

#     - name: Clone eda-alertmanager repository
#       ansible.builtin.git:
#         repo: http://gitea:3000/student/eda-alertmanager.git
#         dest: /tmp/eda-alertmanager

#     - name: Allow user to linger
#       ansible.builtin.command: 
#         cmd: loginctl enable-linger rhel

#     - name: Start node_exporter services with podman-compose
#       ansible.builtin.command:
#         cmd: podman-compose up -d
#         chdir: /tmp/eda-alertmanager/node_exporter

EOF

ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml

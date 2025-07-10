#!/bin/bash

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# Install collection(s)
ansible-galaxy collection install ansible.eda
ansible-galaxy collection install community.general

# # ## setup rhel user
# touch /etc/sudoers.d/rhel_sudoers
# echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
# cp -a /root/.ssh/* /home/$USER/.ssh/.
# chown -R rhel:rhel /home/$USER/.ssh

tee /tmp/inventory << EOF
[nodes]
rhel-1
rhel-2

[all]
podman
rhel-1
rhel-2
aap

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

EOF

# # test secrets in playbook
# tee /tmp/test.yml << EOF
# ---
# - name: Setup podman and services
#   hosts: podman
#   gather_facts: true
#   tasks:

#   - name: put password in /tmp
#     ansible.builtin.command:
#       cmd: echo "task {{ lookup('ansible.builtin.env', 'admin_password') }}" >> /tmp/passwd

# ...
# EOF

# # chown files
# sudo chown rhel:rhel /tmp/test.yml
# sudo chown rhel:rhel /tmp/inventory

# run above playbook
# su - rhel -c 'ansible-playbook -i /tmp/inventory /tmp/test.yml'

# # # creates a playbook to setup environment
###
### Automation Controller setup 
###
- name: Setup Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller

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



  # - name: (DECISIONS) Update EVENT_STREAM_BASE_URL in settings.yaml
  #   ansible.builtin.lineinfile:
  #     path: "/home/rhel/aap/eda/etc/settings.yaml"
  #     regexp: "^EVENT_STREAM_BASE_URL:.*"
  #     line: "EVENT_STREAM_BASE_URL: 'https://{{ ansible_hostname }}.{{ sandbox_id }}.instruqt.io/eda-event-streams'"
  #     backrefs: yes
  #   vars:
  #     sandbox_id: "{{ lookup('env', '_SANDBOX_ID') }}"

  # - name: (DECISIONS) Restart EDA services as rhel user
  #   become: true
  #   become_user: rhel
  #   ansible.builtin.systemd_service:
  #     scope: user
  #     name: "{{ item }}"
  #     state: restarted
  #   loop:
  #     - automation-eda-activation-worker-1.service
  #     - automation-eda-activation-worker-2.service
  #     - automation-eda-api.service
  #     - automation-eda-daphne.service
  #     - automation-eda-scheduler.service
  #     - automation-eda-web.service
  #     - automation-eda-worker-1.service
  #     - automation-eda-worker-2.service
  #   register: restart_services
  #   until: restart_services is not failed
  #   retries: 5
  #   delay: 10


###
# ### RHEL nodes setup 
# ###
- name: Setup rhel nodes
  hosts: nodes
  become: true
  tasks:

    # - name: Add search to resolv.conf
    #   ansible.builtin.shell:
    #     cmd: echo "search $_SANDBOX_ID.svc.cluster.local." >> /etc/resolv.conf
    #   become: true

    # - name: Install epel-release
    #   ansible.builtin.dnf:
    #     name: https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    #     state: present
    #     disable_gpg_check: true

    - name: Install packages
      ansible.builtin.dnf:
        name:
          - git
          - podman-compose
        state: present

    - name: Clone eda-alertmanager repository
      ansible.builtin.git:
        repo: http://podman:3000/student/eda-alertmanager.git
        dest: /tmp/eda-alertmanager

    - name: Allow user to linger
      ansible.builtin.command: 
        cmd: loginctl enable-linger rhel

    - name: Start node_exporter services with podman-compose
      ansible.builtin.command:
        cmd: podman-compose up -d
        chdir: /tmp/eda-alertmanager/node_exporter

# ...
# EOF

ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml

# Vagrant::AnsibleAuto

[![CI](https://github.com/tomeon/vagrant-ansible_auto/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/tomeon/vagrant-ansible_auto/actions/workflows/ci.yml)
[![Code Climate](https://codeclimate.com/github/tomeon/vagrant-ansible_auto.png)](https://codeclimate.com/github/tomeon/vagrant-ansible_auto)
[![Coverage Status](https://coveralls.io/repos/github/tomeon/vagrant-ansible_auto/badge.svg?branch=master)](https://coveralls.io/github/tomeon/vagrant-ansible_auto?branch=master)
[![Gem Version](https://img.shields.io/gem/v/vagrant-ansible_auto.svg)](https://rubygems.org/gems/vagrant-ansible_auto)

This Vagrant plugin provides the `ansible_auto` provisioner that automatically
sets up the provisioned guest as an Ansible control machine for the nodes
defined in your Vagrantfile.  It also provides the `vagrant ansible` subcommand
that generates an inventory file for use on your Vagrant host machine.

## Installation

Install with:

```shell
$ vagrant plugin install vagrant-ansible_auto
```

## Usage

### Inventory Generation

Say you have a Vagrantfile with the following contents:

```ruby
Vagrant.configure(2) do |config|
  config.vm.box = 'hashicorp/precise64'

  (1..2).each do |i|
    name = "ansible-test-worker-#{i}"
    config.vm.define name do |target|
    end
  end

  config.vm.define 'ansible-test-control' do |machine|
    machine.vm.provision :ansible_auto do |ansible|
      ansible.limit = '*'
      ansible.playbook = 'playbooks/test.yml'
    end
  end

  config.ansible.groups = {
    'control'           => %w(ansible-test-control),
    'worker'            => %w(ansible-test-worker-1 ansible-test-worker-2),
    'cluster:children'  => %w(control worker),
  }
end
```

Running `vagrant ansible inventory` will print this Ansible inventory:

```ini
ansible-test-worker-1 ansible_ssh_user=vagrant ansible_ssh_host=127.0.0.1 ansible_ssh_port=2222 ansible_ssh_private_key_file=/home/user/vagrant/cluster/.vagrant/machines/ansible-test-worker-1/virtualbox/private_key
ansible-test-worker-2 ansible_ssh_user=vagrant ansible_ssh_host=127.0.0.1 ansible_ssh_port=2200 ansible_ssh_private_key_file=/home/user/vagrant/cluster/.vagrant/machines/ansible-test-worker-2/virtualbox/private_key
ansible-test-control ansible_ssh_user=vagrant ansible_ssh_host=127.0.0.1 ansible_ssh_port=2201 ansible_ssh_private_key_file=/home/user/vagrant/cluster/.vagrant/machines/ansible-test-control/virtualbox/private_key
[control]
ansible-test-control
[worker]
ansible-test-worker-1
ansible-test-worker-2
[cluster:children]
control
worker
```

You can print the inventory as compact JSON by providing the `--json` flag or
as pretty JSON by providing the `--pretty` flag.

### Provisioning

The `ansible_auto` provisioner is an augmented version of the
[`ansible_local` provisioner included with Vagrant](https://www.vagrantup.com/docs/provisioning/ansible_local.html).
It accepts all options valid for that provisioner, and adds the following
options:

```ruby
Vagrant.configure(2) do |config|
  config.define 'ansible-control' do |machine|
    machine.provision :ansible_auto do |ansible|
      # Will show up in inventory as
      #   [control]
      #   ansible-control
      ansible.groups = {
        'control'   => %w(ansible-control)
      }

      # Will show up in inventory as
      #  [dev:children]
      #  control
      ansible.children = {
        'dev'   => %w(control)
      }

      # Will show up in inventory as
      #   [dev:vars]
      #   git_branch = devel
      ansible.vars = {
        'dev' => {
          'git_branch' => 'devel'
        }
      }

      # Enable or disable the `StrictHostKeyChecking` SSH option.
      # Disabled by default.
      ansible.strict_host_key_checking = false

      # The number of times to attempt to connect to a managed host from the
      # Ansible control machine.
      ansible.host_connect_tries = 10

      # The number of seconds to delay between connection attempts.
      ansible.host_connect_sleep = 5

      # When true, insert the public key of the SSH user for the control
      # machine (the machine that will run `ansible-playbook`) into the
      # authorized_keys files of the SSH users on managed machines.  Enabled by
      # default.
      ansible.insert_control_machine_public_key = false

      # When true, upload the private keys for the SSH users of managed
      # machines to a temporary location on the control machine, using these
      # keys as the values of `ansible_ssh_private_key_file` in the generated
      # inventory.  Disabled by default, unless
      # `insert_control_machine_public_key` is disabled.
      ansible.upload_inventory_host_private_keys = true

      # Add machines that have not been created yet to the inventory.  Accepts
      # `true` (all such machines), `false` (none), or a machine name, regular
      # expression, or list of names and regular expressions.  Disabled by
      # default.  See "Inactive Machines" below.
      ansible.include_inactive_machines = %w(ansible-worker-1 ansible-worker-2)
    end
  end
end
```

#### Public Key Authentication

Each guest provisioned with `ansible_auto` will be set up as an Ansible
control machine with the ability to connect to other guests defined in the
`Vagrantfile`.  This is facilitated by either:

- Inserting the public key of the control machine's SSH user into the
  `authorized_keys` file of the SSH user on each of the managed machines (other
  than the control machine itself).  This is what happens when the option
  `insert_control_machine_public_key` is in effect.
- Uploading the private keys of each guest to a temporary path on the control
  machine and assigning this path as the hostvar `ansible_ssh_private_key_file`
  to the relevant host in the generated inventory.  This is what happens when
  the option `upload_inventory_host_private_keys` is in effect.

`insert_control_machine_public_key` takes precedence over
`upload_inventory_host_private_keys`, so public key insertion will be used if
both options are set to `true`.

#### Targeted Machines

By default, the `ansible_auto` provisioner targets all machines defined in the
inventory by setting the provisioner option `ansible.limit` to `"*"`.  This is
different than the core `ansible_local` provisioner, which by default targets
only the guest for which the provisioner was defined.

#### Inactive Machines

By default, the inventory generated by the `ansible_auto` provisioner has host
entries, with connection variables, only for *active* machines -- those that
Vagrant has created, as returned by `Vagrant::Environment#active_machines`.
Machines that are defined in the `Vagrantfile` but not yet created (for
instance, because they are defined after the machine being provisioned, or
because they were not named in `vagrant up`) get no host entry.

An inactive machine named in the `groups` option still appears in that group,
though, and Ansible treats it as a host with no connection variables: Ansible
will try to reach it by its name, using Ansible's default port and user.
Exclude such machines with `ansible.limit` (see below), or add them with
`include_inactive_machines` so that they get connection variables.

Use the `include_inactive_machines` option to add some or all of them:

```ruby
# All inactive machines
ansible.include_inactive_machines = true

# Only the named machines
ansible.include_inactive_machines = %w(ansible-test-worker-1 ansible-test-worker-2)

# Only machines whose names match a regular expression
ansible.include_inactive_machines = /\Aansible-test-worker-/

# Any combination of names and regular expressions
ansible.include_inactive_machines = ['ansible-test-db', /\Aansible-test-worker-/]
```

Since an inactive machine is not running, the provisioner cannot discover its
address, wait for it to accept SSH connections, or configure SSH keys for it.
Instead, it sets these hostvars from the machine's configuration:

- `ansible_ssh_host`: the first static IP address of a `:public_network`, else
  the first static IP address of a `:private_network`, else
  `config.vm.hostname`, else the machine's name
- `ansible_ssh_port`: `config.ssh.guest_port` (by default, `22`)
- `ansible_ssh_user`: `config.ssh.username` (by default, `vagrant`)

Groups and variables from the inactive machine's own `config.ansible` settings
are added to the inventory, as they are for active machines.

Ansible will be unable to connect to an inactive machine until it is created.
With the default `ansible.limit = "*"`, Ansible will try to connect to it, and
`ansible-playbook` will fail because the machine is unreachable.  To avoid
this, exclude inactive machines with `ansible.limit` (for example,
`ansible.limit = "all:!ansible-test-worker-*"`), or have your plays tolerate
unreachable hosts (for example, with the
[`ignore_unreachable`](https://docs.ansible.com/ansible/latest/reference_appendices/playbooks_keywords.html#play)
play keyword).

This option affects only the `ansible_auto` provisioner.  `vagrant ansible
inventory` already includes every machine defined in the `Vagrantfile`.

## Contributing

1. Fork it ( https://github.com/tomeon/vagrant-ansible_auto/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

[The MIT licence](LICENSE.md)

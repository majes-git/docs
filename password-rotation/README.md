# SSR Password Rotation

## Overview

Every Session Smart Router (SSR) is deployed with a set of built-in system accounts:

- `root`
- `t128`
- `admin`

These system accounts exist locally on each router. Unlike regular user accounts — which can be synchronized with external identity providers such as RADIUS or LDAP — system accounts maintain locally stored passwords that are not externally managed.

In many deployments, security policies require regular password rotation for shared or system accounts to comply with internal governance and industry best practices.

SSR leverages the SaltStack infrastructure to automate operational and configuration management tasks in a **conductor-managed** environment.

This document describes how salt states can be used to implement automated password rotation in an SSR deployment.

## Account Types

SSR routers support two different account types:

1. Traditional Linux accounts  
2. SSR accounts  

While SSR accounts are mapped to underlying Linux accounts, they use a separate password database and serve a specialized operational role.

For example, SSR accounts are automatically authenticated into the SSR CLI (PCLI) and can be restricted to non-administrative functions depending on their assigned role.

Because of these architectural differences, password management and rotation must be handled differently for each account type.

### Linux Accounts

In Linux systems, user accounts are defined through several system files, including:

- `/etc/passwd`
- `/etc/shadow`
- `/etc/group`

Each user account maps a username to a unique numeric identifier called the **user ID (UID)**. Similarly, groups are identified by a **group ID (GID)**. Every user account has a primary group and may also belong to additional supplementary groups.

The `id` command can be used to display the username, UID, GID, and group memberships of the currently logged-in user:

```
$ id
uid=1000(t128) gid=1000(t128) groups=1000(t128),10(wheel)
```

Traditionally, a Linux system administrator changes user passwords using the `passwd` command:

```
$ passwd <username>
```

This process can be automated using [the salt user state module](https://docs.saltproject.io/en/latest/ref/states/all/salt.states.user.html).

Example:

```
Change t128 user password:
  user.present:
    - name: t128
    - password: new-password-in-cleartext
    - hash_password: True
```

In this example, `hash_password: True` ensures that salt hashes the password before applying it to the system.


### SSR Accounts

Although SSR accounts are also represented as Linux accounts, their passwords cannot be changed using the standard `passwd` command. SSR maintains additional backend files that must remain synchronized, including:

- `/var/lib/128technology/user-running.json`
- Other internal SSR state files

Directly modifying the Linux password database would result in inconsistent authentication behavior.

To properly change an SSR account password, an API call must be made to the local SSR conductor or router:

```
PATCH https://localhost/api/v1/user/<username>
```

For automated password rotation through salt, the following tool can be used: [https://github.com/majes-git/ssr-scripts/tree/main/ssr-passwd](https://github.com/majes-git/ssr-scripts/tree/main/ssr-passwd)

The `ssr-passwd.pyz` script interacts with the local router API to ensure that all relevant backend files are updated consistently.


## Salt States

### Overview

Salt (SaltStack) is a configuration management and automation framework that enables centralized control of distributed systems.

A **salt state** defines the desired configuration of a system in a declarative format. States describe *what* the system should look like rather than *how* to achieve it.

When applied, salt evaluates the current system state and enforces compliance with the defined configuration.

Salt states are **idempotent**, meaning they only apply changes when the current configuration deviates from the defined desired state.

### Grains vs. Pillars

Salt provides two primary mechanisms for storing and accessing data: **Grains** and **Pillars**.

#### Grains

Grains are static pieces of information collected from the minion (managed router node). They describe properties of the system itself, such as:

- Hostname  
- Hardware details  

Grains are typically used for targeting and conditional logic but **should not** be used to store sensitive information such as passwords.

#### Pillars

Pillars are secure, centrally managed data structures defined on the conductor (salt master). Pillars are distributed only to authorized minions.

They are commonly used to store:

- Sensitive data (e.g. passwords)  
- Configuration variables

For password rotation in SSR environments, sensitive values such as rotated passwords should be stored in **Pillars** rather than **Grains** to ensure proper security and separation of concerns.

## Putting all together

In preparation for the salt state that implements password rotation (`password-change.sls`), it is recommended to set up the pillar structure that provides the (hashed) passwords.

For SSR users, passwords must be provided in cleartext, as required by the API during password changes.

It is possible to define a pillar per router or a global pillar that acts as a fallback if no router-specific pillar exists.

### Individual vs. Global Passwords

The salt pillars are structured in similar fashion as the salt states itself. Pillars are placed under `/srv/pillar` on the conductor, e.g. like:

```
/srv/pillar/
├── top.sls
├── passwords.sls              # global fallback
└── routers/
    ├── serial-123.sls
    ├── serial-456.sls
    └── ...
```

The `/srv/pillar/top.sls` file specifies which pillar files are assigned to which routers. In the following example, every router should get `/srv/pillar/passwords.sls` and `/srv/pillar/routers/<minion_id>.sls`

```
$ cat /srv/pillar/top.sls
base:
  '*':
    - passwords
    - routers.{{ grains['id'] }}
```

The pillar content for `passwords.sls` and the router-specific files may look as follows:

```
# password hashes can be generated using:
# $ python3 -c "import crypt; print(crypt.crypt('password', crypt.mksalt(crypt.METHOD_SHA512)))"

passwords:
  root:
    hash: "$6$..."
  t128:
    hash: "$6$..."
  admin:
    clear: HPE-Networking.128
```

### password-change.sls

This salt state manages password rotation for all three accounts:

- `root`
- `t128`
- `admin`

To install the salt state, copy the files `password-change.sls` and `ssr-passwd.pyz` on the conductor under `/srv/salt` and add a reference in `/srv/salt/top.sls`:

```
$ cd /srv/salt
$ sudo curl -LO https://github.com/majes-git/ssr-scripts/raw/refs/heads/main/ssr-passwd/ssr-passwd.pyz
$ sudo curl -LO https://github.com/majes-git/docs/raw/refs/heads/main/password-rotation/password-change.sls
```

```
$ cat /srv/salt/top.sls
base:
  '*':
    - password-change
```

For testing purposes, the salt state can executed from the conductor:

```
$ sudo t128-salt serial-123 state.apply password-change
```

... or on the router with `salt-call`:

```
$ sudo salt-call state.apply password-change
```

#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# shellcheck disable=SC2016
set -eux

systemd-analyze log-level debug
export SYSTEMD_LOG_LEVEL=debug

mkdir -p /tmp/img/usr/lib/systemd/system/
mkdir -p /tmp/img/opt/

touch /tmp/img/opt/script0.sh
chmod +x /tmp/img/opt/script0.sh

cat <<EOF >/tmp/img/usr/lib/systemd/system/testfile.service
[Service]
ExecStart = /opt/script0.sh
EOF

set +e
# Default behaviour is to recurse through all dependencies when unit is loaded
systemd-analyze verify --root=/tmp/img/ testfile.service \
    && { echo 'unexpected success'; exit 1; }

# As above, recurses through all dependencies when unit is loaded
systemd-analyze verify --recursive-errors=yes --root=/tmp/img/ testfile.service \
    && { echo 'unexpected success'; exit 1; }

# Recurses through unit file and its direct dependencies when unit is loaded
systemd-analyze verify --recursive-errors=one --root=/tmp/img/ testfile.service \
    && { echo 'unexpected success'; exit 1; }

set -e

# zero exit status since dependencies are ignored when unit is loaded
systemd-analyze verify --recursive-errors=no --root=/tmp/img/ testfile.service

rm /tmp/img/usr/lib/systemd/system/testfile.service

cat <<EOF >/tmp/testfile.service
[Unit]
foo = bar

[Service]
ExecStart = echo hello
EOF

cat <<EOF >/tmp/testfile2.service
[Unit]
Requires = testfile.service

[Service]
ExecStart = echo hello
EOF

# Zero exit status since no additional dependencies are recursively loaded when the unit file is loaded
systemd-analyze verify --recursive-errors=no /tmp/testfile2.service

set +e
# Non-zero exit status since all associated dependencies are recursively loaded when the unit file is loaded
systemd-analyze verify --recursive-errors=yes /tmp/testfile2.service \
    && { echo 'unexpected success'; exit 1; }
set -e

rm /tmp/testfile.service
rm /tmp/testfile2.service

cat <<EOF >/tmp/testfile.service
[Service]
ExecStart = echo hello
EOF

# Prevent regression from #13380 and #20859 where we can't verify hidden files
cp /tmp/testfile.service /tmp/.testfile.service

systemd-analyze verify /tmp/.testfile.service

rm /tmp/.testfile.service

# Alias a unit file's name on disk (see #20061)
cp /tmp/testfile.service /tmp/testsrvc

systemd-analyze verify /tmp/testsrvc \
    && { echo 'unexpected success'; exit 1; }

systemd-analyze verify /tmp/testsrvc:alias.service

# Zero exit status since the value used for comparison determine exposure to security threats is by default 100
systemd-analyze security --offline=true /tmp/testfile.service

set +e
#The overall exposure level assigned to the unit is greater than the set threshold
systemd-analyze security --threshold=90 --offline=true /tmp/testfile.service \
    && { echo 'unexpected success'; exit 1; }
set -e

rm /tmp/testfile.service

cat <<EOF >/tmp/img/usr/lib/systemd/system/testfile.service
[Service]
ExecStart = echo hello
PrivateNetwork = yes
PrivateDevices = yes
PrivateUsers = yes
EOF

# The new overall exposure level assigned to the unit is less than the set thresholds
# Verifies that the --offline= option works with --root=
systemd-analyze security --threshold=90 --offline=true --root=/tmp/img/ testfile.service

# Added an additional "INVALID_ID" id to the .json to verify that nothing breaks when input is malformed
# The PrivateNetwork id description and weight was changed to verify that 'security' is actually reading in
# values from the .json file when required. The default weight for "PrivateNetwork" is 2500, and the new weight
# assigned to that id in the .json file is 6000. This increased weight means that when the "PrivateNetwork" key is
# set to 'yes' (as above in the case of testfile.service) in the content of the unit file, the overall exposure
# level for the unit file should decrease to account for that increased weight.
cat <<EOF >/tmp/testfile.json
{"UserOrDynamicUser":
    {"description_bad": "Service runs as root user",
    "weight": 0,
    "range": 10
    },
"SupplementaryGroups":
    {"description_good": "Service has no supplementary groups",
    "description_bad": "Service runs with supplementary groups",
    "description_na": "Service runs as root, option does not matter",
    "weight": 200,
    "range": 1
    },
"PrivateDevices":
    {"description_good": "Service has no access to hardware devices",
    "description_bad": "Service potentially has access to hardware devices",
    "weight": 1000,
    "range": 1
    },
"PrivateMounts":
    {"description_good": "Service cannot install system mounts",
    "description_bad": "Service may install system mounts",
    "weight": 1000,
    "range": 1
    },
"PrivateNetwork":
    {"description_good": "Service doesn't have access to the host's network",
    "description_bad": "Service has access to the host's network",
    "weight": 6000,
    "range": 1
    },
"PrivateTmp":
    {"description_good": "Service has no access to other software's temporary files",
    "description_bad": "Service has access to other software's temporary files",
    "weight": 1000,
    "range": 1
    },
"PrivateUsers":
    {"description_good": "Service does not have access to other users",
    "description_bad": "Service has access to other users",
    "weight": 1000,
    "range": 1
    },
"ProtectControlGroups":
    {"description_good": "Service cannot modify the control group file system",
    "description_bad": "Service may modify the control group file system",
    "weight": 1000,
    "range": 1
    },
"ProtectKernelModules":
    {"description_good": "Service cannot load or read kernel modules",
    "description_bad": "Service may load or read kernel modules",
    "weight": 1000,
    "range": 1
    },
"ProtectKernelTunables":
    {"description_good": "Service cannot alter kernel tunables (/proc/sys, …)",
    "description_bad": "Service may alter kernel tunables",
    "weight": 1000,
    "range": 1
    },
"ProtectKernelLogs":
    {"description_good": "Service cannot read from or write to the kernel log ring buffer",
    "description_bad": "Service may read from or write to the kernel log ring buffer",
    "weight": 1000,
    "range": 1
    },
"ProtectClock":
    {"description_good": "Service cannot write to the hardware clock or system clock",
    "description_bad": "Service may write to the hardware clock or system clock",
    "weight": 1000,
    "range": 1
    },
"ProtectHome":
    {"weight": 1000,
    "range": 10
    },
"ProtectHostname":
    {"description_good": "Service cannot change system host/domainname",
    "description_bad": "Service may change system host/domainname",
    "weight": 50,
    "range": 1
    },
"ProtectSystem":
    {"weight": 1000,
    "range": 10
    },
"RootDirectoryOrRootImage":
    {"description_good": "Service has its own root directory/image",
    "description_bad": "Service runs within the host's root directory",
    "weight": 200,
    "range": 1
    },
"LockPersonality":
    {"description_good": "Service cannot change ABI personality",
    "description_bad": "Service may change ABI personality",
    "weight": 100,
    "range": 1
    },
"MemoryDenyWriteExecute":
    {"description_good": "Service cannot create writable executable memory mappings",
    "description_bad": "Service may create writable executable memory mappings",
    "weight": 100,
    "range": 1
    },
"NoNewPrivileges":
    {"description_good": "Service processes cannot acquire new privileges",
    "description_bad": "Service processes may acquire new privileges",
    "weight": 1000,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_ADMIN":
    {"description_good": "Service has no administrator privileges",
    "description_bad": "Service has administrator privileges",
    "weight": 1500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SET_UID_GID_PCAP":
    {"description_good": "Service cannot change UID/GID identities/capabilities",
    "description_bad": "Service may change UID/GID identities/capabilities",
    "weight": 1500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_PTRACE":
    {"description_good": "Service has no ptrace() debugging abilities",
    "description_bad": "Service has ptrace() debugging abilities",
    "weight": 1500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_TIME":
    {"description_good": "Service processes cannot change the system clock",
    "description_bad": "Service processes may change the system clock",
    "weight": 1000,
    "range": 1
    },
"CapabilityBoundingSet_CAP_NET_ADMIN":
    {"description_good": "Service has no network configuration privileges",
    "description_bad": "Service has network configuration privileges",
    "weight": 1000,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_RAWIO":
    {"description_good": "Service has no raw I/O access",
    "description_bad": "Service has raw I/O access",
    "weight": 1000,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_MODULE":
    {"description_good": "Service cannot load kernel modules",
    "description_bad": "Service may load kernel modules",
    "weight": 1000,
    "range": 1
    },
"CapabilityBoundingSet_CAP_AUDIT":
    {"description_good": "Service has no audit subsystem access",
    "description_bad": "Service has audit subsystem access",
    "weight": 500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYSLOG":
    {"description_good": "Service has no access to kernel logging",
    "description_bad": "Service has access to kernel logging",
    "weight": 500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_NICE_RESOURCE":
    {"description_good": "Service has no privileges to change resource use parameters",
    "description_bad": "Service has privileges to change resource use parameters",
    "weight": 500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_MKNOD":
    {"description_good": "Service cannot create device nodes",
    "description_bad": "Service may create device nodes",
    "weight": 500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_CHOWN_FSETID_SETFCAP":
    {"description_good": "Service cannot change file ownership/access mode/capabilities",
    "description_bad": "Service may change file ownership/access mode/capabilities unrestricted",
    "weight": 1000,
    "range": 1
    },
"CapabilityBoundingSet_CAP_DAC_FOWNER_IPC_OWNER":
    {"description_good": "Service cannot override UNIX file/IPC permission checks",
    "description_bad": "Service may override UNIX file/IPC permission checks",
    "weight": 1000,
    "range": 1
    },
"CapabilityBoundingSet_CAP_KILL":
    {"description_good": "Service cannot send UNIX signals to arbitrary processes",
    "description_bad": "Service may send UNIX signals to arbitrary processes",
    "weight": 500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_NET_BIND_SERVICE_BROADCAST_RAW":
    {"description_good": "Service has no elevated networking privileges",
    "description_bad": "Service has elevated networking privileges",
    "weight": 500,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_BOOT":
    {"description_good": "Service cannot issue reboot()",
    "description_bad": "Service may issue reboot()",
    "weight": 100,
    "range": 1
    },
"CapabilityBoundingSet_CAP_MAC":
    {"description_good": "Service cannot adjust SMACK MAC",
    "description_bad": "Service may adjust SMACK MAC",
    "weight": 100,
    "range": 1
    },
"CapabilityBoundingSet_CAP_LINUX_IMMUTABLE":
    {"description_good": "Service cannot mark files immutable",
    "description_bad": "Service may mark files immutable",
    "weight": 75,
    "range": 1
    },
"CapabilityBoundingSet_CAP_IPC_LOCK":
    {"description_good": "Service cannot lock memory into RAM",
    "description_bad": "Service may lock memory into RAM",
    "weight": 50,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_CHROOT":
    {"description_good": "Service cannot issue chroot()",
    "description_bad": "Service may issue chroot()",
    "weight": 50,
    "range": 1
    },
"CapabilityBoundingSet_CAP_BLOCK_SUSPEND":
    {"description_good": "Service cannot establish wake locks",
    "description_bad": "Service may establish wake locks",
    "weight": 25,
    "range": 1
    },
"CapabilityBoundingSet_CAP_WAKE_ALARM":
    {"description_good": "Service cannot program timers that wake up the system",
    "description_bad": "Service may program timers that wake up the system",
    "weight": 25,
    "range": 1
    },
"CapabilityBoundingSet_CAP_LEASE":
    {"description_good": "Service cannot create file leases",
    "description_bad": "Service may create file leases",
    "weight": 25,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_TTY_CONFIG":
    {"description_good": "Service cannot issue vhangup()",
    "description_bad": "Service may issue vhangup()",
    "weight": 25,
    "range": 1
    },
"CapabilityBoundingSet_CAP_SYS_PACCT":
    {"description_good": "Service cannot use acct()",
    "description_bad": "Service may use acct()",
    "weight": 25,
    "range": 1
    },
"UMask":
    {"weight": 100,
    "range": 10
    },
"KeyringMode":
    {"description_good": "Service doesn't share key material with other services",
    "description_bad": "Service shares key material with other service",
    "weight": 1000,
    "range": 1
    },
"ProtectProc":
    {"description_good": "Service has restricted access to process tree(/proc hidepid=)",
    "description_bad": "Service has full access to process tree(/proc hidepid=)",
    "weight": 1000,
    "range": 3
    },
"ProcSubset":
    {"description_good": "Service has no access to non-process/proc files(/proc subset=)",
    "description_bad": "Service has full access to non-process/proc files(/proc subset=)",
    "weight": 10,
    "range": 1
    },
"NotifyAccess":
    {"description_good": "Service child processes cannot alter service state",
    "description_bad": "Service child processes may alter service state",
    "weight": 1000,
    "range": 1
    },
"RemoveIPC":
    {"description_good": "Service user cannot leave SysV IPC objects around",
    "description_bad": "Service user may leave SysV IPC objects around",
    "description_na": "Service runs as root, option does not apply",
    "weight": 100,
    "range": 1
    },
"Delegate":
    {"description_good": "Service does not maintain its own delegated control group subtree",
    "description_bad": "Service maintains its own delegated control group subtree",
    "weight": 100,
    "range": 1
    },
"RestrictRealtime":
    {"description_good": "Service realtime scheduling access is restricted",
    "description_bad": "Service may acquire realtime scheduling",
    "weight": 500,
    "range": 1
    },
"RestrictSUIDSGID":
    {"description_good": "SUID/SGIDfilecreationbyserviceisrestricted",
    "description_bad": "ServicemaycreateSUID/SGIDfiles",
    "weight": 1000,
    "range": 1
    },
"RestrictNamespaces_user":
    {"description_good": "Servicecannotcreateusernamespaces",
    "description_bad": "Servicemaycreateusernamespaces",
    "weight": 1500,
    "range": 1
    },
"RestrictNamespaces_mnt":
    {"description_good": "Service cannot create file system namespaces",
    "description_bad": "Service may create file system namespaces",
    "weight": 500,
    "range": 1
    },
"RestrictNamespaces_ipc":
    {"description_good": "Service cannot create IPC namespaces",
    "description_bad": "Service may create IPC namespaces",
    "weight": 500,
    "range": 1
    },
"RestrictNamespaces_pid":
    {"description_good": "Service cannot create process namespaces",
    "description_bad": "Service may create process namespaces",
    "weight": 500,
    "range": 1
    },
"RestrictNamespaces_cgroup":
    {"description_good": "Service cannot create cgroup namespaces",
    "description_bad": "Service may create cgroup namespaces",
    "weight": 500,
    "range": 1
    },
"RestrictNamespaces_net":
    {"description_good": "Service cannot create network namespaces",
    "description_bad": "Service may create network namespaces",
    "weight": 500,
    "range": 1
    },
"RestrictNamespaces_uts":
    {"description_good": "Service cannot create hostname namespaces",
    "description_bad": "Service may create hostname namespaces",
    "weight": 100,
    "range": 1
    },
"RestrictAddressFamilies_AF_INET_INET6":
    {"description_good": "Service cannot allocate Internet sockets",
    "description_bad": "Service may allocate Internet sockets",
    "weight": 1500,
    "range": 1
    },
"RestrictAddressFamilies_AF_UNIX":
    {"description_good": "Service cannot allocate local sockets",
    "description_bad": "Service may allocate local sockets",
    "weight": 25,
    "range": 1
    },
"RestrictAddressFamilies_AF_NETLINK":
    {"description_good": "Service cannot allocate netlink sockets",
    "description_bad": "Service may allocate netlink sockets",
    "weight": 200,
    "range": 1
    },
"RestrictAddressFamilies_AF_PACKET":
    {"description_good": "Service cannot allocate packet sockets",
    "description_bad": "Service may allocate packet sockets",
    "weight": 1000,
    "range": 1
    },
"RestrictAddressFamilies_OTHER":
    {"description_good": "Service cannot allocate exotic sockets",
    "description_bad": "Service may allocate exotic sockets",
    "weight": 1250,
    "range": 1
    },
"SystemCallArchitectures":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_swap":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_obsolete":
    {"weight": 250,
    "range": 10
    },
"SystemCallFilter_clock":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_cpu_emulation":
    {"weight": 250,
    "range": 10
    },
"SystemCallFilter_debug":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_mount":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_module":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_raw_io":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_reboot":
    {"weight": 1000,
    "range": 10
    },
"SystemCallFilter_privileged":
    {"weight": 700,
    "range": 10
    },
"SystemCallFilter_resources":
    {"weight": 700,
    "range": 10
    },
"IPAddressDeny":
    {"weight": 1000,
    "range": 10
    },
"DeviceAllow":
    {"weight": 1000,
    "range": 10
    },
"AmbientCapabilities":
    {"description_good": "Service process does not receive ambient capabilities",
    "description_bad": "Service process receives ambient capabilities",
    "weight": 500,
    "range": 1
    },
"INVALID_ID":
    {"weight": 1000,
    "range": 10
    }
}
EOF

# Reads in custom security requirements from the parsed .json file and uses these for comparison
systemd-analyze security --threshold=90 --offline=true \
                           --security-policy=/tmp/testfile.json \
                           --root=/tmp/img/ testfile.service

# The strict profile adds a lot of sanboxing options
systemd-analyze security --threshold=20 --offline=true \
                           --security-policy=/tmp/testfile.json \
                           --profile=strict \
                           --root=/tmp/img/ testfile.service

set +e
# The trusted profile doesn't add any sanboxing options
systemd-analyze security --threshold=20 --offline=true \
                           --security-policy=/tmp/testfile.json \
                           --profile=/usr/lib/systemd/portable/profile/trusted/service.conf \
                           --root=/tmp/img/ testfile.service \
    && { echo 'unexpected success'; exit 1; }

systemd-analyze security --threshold=50 --offline=true \
                           --security-policy=/tmp/testfile.json \
                           --root=/tmp/img/ testfile.service \
    && { echo 'unexpected success'; exit 1; }
set -e

rm /tmp/img/usr/lib/systemd/system/testfile.service

if systemd-analyze --version | grep -q -F "+ELFUTILS"; then
    systemd-analyze inspect-elf --json=short /lib/systemd/systemd | grep -q -F '"elfType":"executable"'
fi

systemd-analyze log-level info

echo OK >/testok

exit 0

# Ansible role for motionEye

[![Build Status](https://travis-ci.org/mathieumd/ansible-role-motioneye.svg)](https://travis-ci.org/mathieumd/ansible-role-motioneye)

Install and update [motionEye](http://www.lavrsen.dk/foswiki/bin/view/Motion/MotionEye), a web-based user interface for [Motion](http://www.lavrsen.dk/foswiki/bin/view/Motion/WebHome).

## Role Variables

See the comments into [defaults](defaults/main.yml).

```yaml
motioneye_version: "0.21"
# motioneye_version: HEAD

motioneye_user: motion
motioneye_group: motion
motioneye_path: /opt/motioneye

motioneye_media_path: /srv/motioneye

motioneye_settings:
  MEDIA_PATH: "'{{ motioneye_media_path }}'"

motioneye_enable_when_away: no
# motioneye_ewa_monitors_id: "1"
# motioneye_ewa_known_hosts:
#   - ip: "192.168.0.100"
#     mac: "aa:bb:cc:dd:ee:ff"
```

## Example Playbook

```yaml
- hosts: servers
  roles:
     - role: ansible-role-motioneye
```

## License

GPLv3


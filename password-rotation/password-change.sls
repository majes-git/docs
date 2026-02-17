{% for username in ['root', 't128'] %}
{% set password_hash = salt['pillar.get']('passwords:' ~ username ~ ':hash') %}
change_password_{{ username }}:
  user.present:
    - name: {{ username }}
    - password: {{ password_hash }}
{% endfor %}

{% set sbin_path = "/usr/local/bin" %}
{% set pyz = "ssr-passwd.pyz" %}
install_ssr_passwd:
  file.managed:
    - name: {{ sbin_path }}/{{ pyz }}
    - mode: 755
    - source: salt://{{ pyz }}

{% set password = salt['pillar.get']('passwords:admin:clear') %}
change_password_admin:
  cmd.run:
    - name: {{ sbin_path }}/{{ pyz }} change
    - unless: {{ sbin_path }}/{{ pyz }} check
    - env:
        NEW_PASSWORD: "{{ password }}"

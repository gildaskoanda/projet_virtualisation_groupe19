# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# RÉSULTATS-BF — source unique de vérité de l'infrastructure.
#
# La table NOEUDS décrit toutes les machines ET engendre la configuration
# du répartiteur (config/noeuds.tsv, lu par scripts/lb.sh) : c'est cette
# propriété unique qui rend l'exigence R3 possible — passer de 2 à N
# serveurs applicatifs sans toucher à la configuration du répartiteur.

require 'fileutils'
require 'securerandom'
require 'yaml'

# --- Paramètres (variables d'environnement, valeurs par défaut sûrs) -------
GROUPE  = (ENV['GROUPE'] || 1).to_i
NB_APP  = (ENV['NB_APP'] || 2).to_i
# Sous-réseau : surchargeable via RESEAU si l'enseignant attribue un
# sous-réseau différent au groupe (la règle 55+G ne couvre que G=1..8).
RESEAU  = ENV['RESEAU'] || "192.168.#{55 + GROUPE}"
VIP     = "#{RESEAU}.10"

# Détection du fournisseur : vagrant-libvirt (KVM) s'il est installé,
# sinon VirtualBox (environnement d'évaluation imposé par le cahier des charges).
PROVIDER = ENV.fetch('VAGRANT_DEFAULT_PROVIDER') do
  Vagrant.has_plugin?('vagrant-libvirt') ? 'libvirt' : 'virtualbox'
end

# Boîte épinglée, identique pour tous les membres : présente à la fois pour
# virtualbox et libvirt sur cette version (bento/ubuntu-24.04).
BOITE         = 'bento/ubuntu-24.04'
VERSION_BOITE = '202502.21.0'

# --- Secrets (R7) ----------------------------------------------------------
# .env est ignoré par Git ; .env.exemple en est le modèle versionné.
# Au premier déclenchement, .env est engendré avec des mots de passe
# aléatoires : la reconstruction (R1) n'exige aucun geste manuel.
def ecrire_env_si_absent
  return if File.exist?('.env')
  alea = -> { SecureRandom.alphanumeric(24) }
  File.write('.env', <<~ENV)
    DB_USER=resultats
    DB_PASSWORD=#{alea.call}
    DB_NAME=resultats
    DB_REPL_USER=replique
    DB_REPL_PASSWORD=#{alea.call}
    GRAFANA_MDP=#{alea.call}
  ENV
  puts '[resultats-bf] .env absent : engendré avec des mots de passe aleatoires.'
end

def lire_env
  ecrire_env_si_absent
  valeurs = {}
  File.readlines('.env').each do |ligne|
    ligne = ligne.strip
    next if ligne.empty? || ligne.start_with?('#')
    cle, val = ligne.split('=', 2)
    valeurs[cle.strip] = val.strip if cle && val
  end
  %w[DB_USER DB_PASSWORD DB_NAME DB_REPL_USER DB_REPL_PASSWORD].each do |c|
    abort "[resultats-bf] cle #{c} absente ou vide dans .env" if valeurs[c].nil? || valeurs[c].empty?
  end
  valeurs
end

SECRETS = lire_env

# --- Table des machines : source unique de vérité --------------------------
NOEUDS = []
NOEUDS << { nom: 'bdd1', ip: "#{RESEAU}.31", mem: 768, role: 'bdd' }
NOEUDS << { nom: 'bdd2', ip: "#{RESEAU}.32", mem: 768, role: 'replique' }
(1..NB_APP).each do |i|
  NOEUDS << { nom: "app#{i}", ip: "#{RESEAU}.#{20 + i}", mem: 512, role: 'app' }
end
NOEUDS << { nom: 'lb1', ip: "#{RESEAU}.11", mem: 512, role: 'lb', vip: VIP, prio: 110 }
NOEUDS << { nom: 'lb2', ip: "#{RESEAU}.12", mem: 512, role: 'lb', vip: VIP, prio: 100 }
NOEUDS << { nom: 'obs', ip: "#{RESEAU}.41", mem: 768, role: 'obs' }

# Engendrement des fichiers lus par les scripts de provisionnement.
# La configuration du répartiteur dérive de ce tableau (R3, R8).
FileUtils.mkdir_p('config')
File.write('config/noeuds.yml', NOEUDS.to_yaml)
File.write(
  'config/noeuds.tsv',
  NOEUDS.map { |n| [n[:nom], n[:ip], n[:role], n[:vip] || '-', n[:prio] || '-'].join("\t") }.join("\n") + "\n"
)

# --- Machines virtuelles ---------------------------------------------------
Vagrant.configure('2') do |config|
  config.vm.box          = BOITE
  config.vm.box_version  = VERSION_BOITE
  config.vm.boot_timeout = 600

  # Tout est envoyé par des provisionneurs « file » : aucune dépendance
  # au dossier synchronisé (fragile sous libvirt, inutile ici).
  config.vm.synced_folder '.', '/vagrant', disabled: true

  NOEUDS.each do |n|
    config.vm.define n[:nom] do |m|
      m.vm.hostname = n[:nom]
      m.vm.network 'private_network', ip: n[:ip]

      # R8 : seul le répartiteur actif expose un port vers l'hôte.
      if n[:nom] == 'lb1' && PROVIDER == 'virtualbox'
        m.vm.network 'forwarded_port', guest: 80, host: 8080, host_ip: '127.0.0.1'
      end

      m.vm.provider 'virtualbox' do |vb|
        vb.memory        = n[:mem]
        vb.cpus          = 1
        vb.linked_clone  = true
      end
      m.vm.provider 'libvirt' do |lv|
        lv.memory = n[:mem]
        lv.cpus   = 1
      end

      # Fichiers nécessaires au provisionnement.
      m.vm.provision 'file', source: 'scripts/lib/lib.sh', destination: '/tmp/lib.sh'
      m.vm.provision 'file', source: 'config/noeuds.tsv', destination: '/tmp/noeuds.tsv'
      m.vm.provision 'file', source: 'app/app.py',        destination: '/tmp/app.py'
      m.vm.provision 'file', source: 'sql/schema.sql',    destination: '/tmp/schema.sql'
      if n[:role] == 'obs'
        m.vm.provision 'file', source: 'config/dashboards/resultats-bf.json',
                        destination: '/tmp/dashboard.json'
      end

      m.vm.provision 'shell', path: 'scripts/base.sh'
      m.vm.provision 'shell', path: "scripts/#{n[:role]}.sh", env: {
        'DB_USER'         => SECRETS['DB_USER'],
        'DB_PASSWORD'     => SECRETS['DB_PASSWORD'],
        'DB_NAME'         => SECRETS['DB_NAME'],
        'DB_REPL_USER'    => SECRETS['DB_REPL_USER'],
        'DB_REPL_PASSWORD'=> SECRETS['DB_REPL_PASSWORD'],
        'GRAFANA_MDP'     => SECRETS['GRAFANA_MDP'] || '',
        'RESEAU'          => RESEAU,
        'VIP'             => VIP,
        'IP'              => n[:ip],
        'NB_APP'          => NB_APP.to_s
      }

      # R3 sans geste manuel : dès qu'un serveur applicatif est allumé, la
      # configuration du répartiteur est engendrée à nouveau depuis la
      # même source de vérité et poussée sans redémarrage (reload).
      if n[:role] == 'app'
        m.trigger.after :up do |t|
          t.name      = 'Mise à jour du répartiteur (source de vérité unique)'
          t.on_error  = :continue
          t.run = {
            inline: 'vagrant upload config/noeuds.tsv /tmp/noeuds.tsv lb1 && vagrant ssh lb1 -c "sudo /usr/local/sbin/rafraichir-haproxy" && vagrant upload config/noeuds.tsv /tmp/noeuds.tsv lb2 && vagrant ssh lb2 -c "sudo /usr/local/sbin/rafraichir-haproxy"'
          }
        end
      end
    end
  end
end

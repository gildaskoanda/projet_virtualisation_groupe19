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

# --- Fichier .env : secrets et paramètres, jamais versionné (R7) -----------
# .env.exemple en est le modèle versionné. Au premier déclenchement, .env est
# engendré avec des mots de passe aléatoires : la reconstruction (R1) n'exige
# aucun geste manuel. File.binwrite : fins de ligne LF même sous Windows.
def ecrire_env_si_absent
  return if File.exist?('.env')
  alea = ->(n = 24) { SecureRandom.alphanumeric(n) }
  File.binwrite('.env', <<~ENV)
    GROUPE=3
    NB_APP=2
    EXTENSIONS=1
    DB_USER=resultats
    DB_PASSWORD=#{alea.call}
    DB_NAME=resultats
    DB_REPL_USER=replique
    DB_REPL_PASSWORD=#{alea.call}
    GRAFANA_MDP=#{alea.call}
    VRRP_PASS=#{alea.call(8)}
  ENV
  puts '[resultats-bf] .env absent : engendré avec des mots de passe aleatoires.'
end

def lire_env
  ecrire_env_si_absent
  valeurs = {}
  contenu = File.read('.env', encoding: 'UTF-8')
  contenu.each_line do |ligne|
    ligne = ligne.strip
    next if ligne.empty? || ligne.start_with?('#')
    cle, val = ligne.split('=', 2)
    valeurs[cle.strip] = val.strip if cle && val
  end
  # .env créé avant l'ajout de VRRP_PASS : on complète sans rien casser.
  if valeurs['VRRP_PASS'].to_s.empty?
    valeurs['VRRP_PASS'] = SecureRandom.alphanumeric(8)
    suite = contenu.end_with?("\n") || contenu.empty? ? '' : "\n"
    File.binwrite('.env', contenu + suite + "VRRP_PASS=#{valeurs['VRRP_PASS']}\n")
    puts '[resultats-bf] VRRP_PASS ajouté à .env.'
  end
  %w[DB_USER DB_PASSWORD DB_NAME DB_REPL_USER DB_REPL_PASSWORD].each do |c|
    abort "[resultats-bf] cle #{c} absente ou vide dans .env" if valeurs[c].nil? || valeurs[c].empty?
  end
  valeurs
end

SECRETS = lire_env

# Une variable d'environnement l'emporte sur .env, qui l'emporte sur le défaut.
def parametre(nom, defaut)
  v = ENV[nom]
  v = SECRETS[nom] if v.nil? || v.empty?
  v.nil? || v.empty? ? defaut : v
end

# --- Paramètres --------------------------------------------------------------
GROUPE     = parametre('GROUPE', '3').to_i       # sous-réseau attribué : groupe 3
NB_APP     = parametre('NB_APP', '2').to_i       # nombre de serveurs applicatifs (R3)
EXTENSIONS = parametre('EXTENSIONS', '1') == '1' # 0 = socle seul (lb2 et obs exclues)
APP_PORT   = '3000'                              # port des serveurs applicatifs
HOTE_PORT  = parametre('HOTE_PORT', '8080').to_i   # port du PC redirigé vers lb1 (R8) : à changer si 8080 est déjà pris

abort '[resultats-bf] GROUPE doit etre compris entre 1 et 8 (plage VirtualBox 192.168.56.0-63.255)' unless (1..8).include?(GROUPE)
abort '[resultats-bf] NB_APP doit etre compris entre 2 et 9' unless (2..9).include?(NB_APP)

RESEAU = "192.168.#{55 + GROUPE}"   # règle imposée : X = 55 + G
VIP    = "#{RESEAU}.5"              # adresse virtuelle VRRP (figure 1 du sujet)

# Boîte épinglée, identique pour tous les membres du groupe.
BOITE         = 'bento/ubuntu-24.04'
VERSION_BOITE = '202502.21.0'

# --- Table des machines : source unique de vérité ---------------------------
NOEUDS = []
NOEUDS << { nom: 'bdd1', ip: "#{RESEAU}.31", mem: 768, role: 'bdd' }
NOEUDS << { nom: 'bdd2', ip: "#{RESEAU}.32", mem: 768, role: 'replique' }
(1..NB_APP).each do |i|
  NOEUDS << { nom: "app#{i}", ip: "#{RESEAU}.#{20 + i}", mem: 512, role: 'app' }
end
NOEUDS << { nom: 'lb1', ip: "#{RESEAU}.11", mem: 512, role: 'lb', vip: VIP, prio: 110 }
if EXTENSIONS
  NOEUDS << { nom: 'lb2', ip: "#{RESEAU}.12", mem: 512, role: 'lb', vip: VIP, prio: 100 } # E1
  NOEUDS << { nom: 'obs', ip: "#{RESEAU}.41", mem: 768, role: 'obs' }                      # E2
end

# Engendrement des fichiers lus par les scripts de provisionnement.
# binwrite : LF partout, y compris sous Windows (sinon « 110\r » casse keepalived).
FileUtils.mkdir_p('config')
File.binwrite('config/noeuds.yml', NOEUDS.map { |n| n.transform_keys(&:to_s) }.to_yaml)
File.binwrite(
  'config/noeuds.tsv',
  NOEUDS.map { |n| [n[:nom], n[:ip], n[:role], n[:vip] || '-', n[:prio] || '-'].join("\t") }.join("\n") + "\n"
)

# --- R3 sans geste manuel -----------------------------------------------------
# Dès qu'un serveur applicatif est allumé, la configuration des répartiteurs
# déjà démarrés est engendrée à nouveau depuis le même tableau et rechargée à
# chaud. Code Ruby (pas de shell) : fonctionne à l'identique sous Windows.
def machine_active?(nom)
  sortie = `vagrant status #{nom} --machine-readable 2>&1`
  sortie.lines.any? do |l|
    c = l.strip.split(',')
    c[2] == 'state' && c[3] == 'running'
  end
end

def rafraichir_repartiteurs
  %w[lb1 lb2].each do |lb|
    next unless NOEUDS.any? { |n| n[:nom] == lb }
    next unless machine_active?(lb)
    system('vagrant', 'upload', 'config/noeuds.tsv', '/tmp/noeuds.tsv', lb)
    system('vagrant', 'ssh', lb, '-c', 'sudo /usr/local/sbin/rafraichir-haproxy')
  end
end

# --- Machines virtuelles -----------------------------------------------------
Vagrant.configure('2') do |config|
  config.vm.box          = BOITE
  config.vm.box_version  = VERSION_BOITE
  config.vm.boot_timeout = 600

  # Tout est envoyé par des provisionneurs « file » : aucune dépendance au
  # dossier synchronisé.
  config.vm.synced_folder '.', '/vagrant', disabled: true

  NOEUDS.each do |n|
    config.vm.define n[:nom] do |m|
      m.vm.hostname = n[:nom]
      m.vm.network 'private_network', ip: n[:ip]

      # R8 : seul le répartiteur principal expose un port vers l'hôte.
      if n[:nom] == 'lb1'
        m.vm.network 'forwarded_port', guest: 80, host: HOTE_PORT, host_ip: '127.0.0.1'
      end

      m.vm.provider 'virtualbox' do |vb|
        vb.name         = "g#{GROUPE}-#{n[:nom]}"
        vb.memory       = n[:mem]
        vb.cpus         = 1
        vb.linked_clone = true
      end

      # Fichiers nécessaires au provisionnement (seulement ceux du rôle).
      m.vm.provision 'file', source: 'scripts/lib/lib.sh', destination: '/tmp/lib.sh'
      m.vm.provision 'file', source: 'config/noeuds.tsv', destination: '/tmp/noeuds.tsv'
      m.vm.provision 'file', source: 'app/app.py',     destination: '/tmp/app.py'     if n[:role] == 'app'
      m.vm.provision 'file', source: 'sql/schema.sql', destination: '/tmp/schema.sql' if n[:role] == 'bdd'
      if n[:role] == 'obs'
        m.vm.provision 'file', source: 'config/dashboards/resultats-bf.json',
                        destination: '/tmp/dashboard.json'
      end

      m.vm.provision 'shell', path: 'scripts/base.sh'
      m.vm.provision 'shell', path: "scripts/#{n[:role]}.sh", env: {
        'DB_USER'          => SECRETS['DB_USER'],
        'DB_PASSWORD'      => SECRETS['DB_PASSWORD'],
        'DB_NAME'          => SECRETS['DB_NAME'],
        'DB_REPL_USER'     => SECRETS['DB_REPL_USER'],
        'DB_REPL_PASSWORD' => SECRETS['DB_REPL_PASSWORD'],
        'GRAFANA_MDP'      => SECRETS['GRAFANA_MDP'] || '',
        'VRRP_PASS'        => SECRETS['VRRP_PASS'],
        'RESEAU'           => RESEAU,
        'VIP'              => VIP,
        'IP'               => n[:ip],
        'APP_PORT'         => APP_PORT,
        'NB_APP'           => NB_APP.to_s
      }

      if n[:role] == 'app'
        m.trigger.after :up do |t|
          t.name     = 'Mise à jour des répartiteurs (source de vérité unique)'
          t.on_error = :continue
          t.ruby { |_env, _machine| rafraichir_repartiteurs }
        end
      end
    end
  end
end

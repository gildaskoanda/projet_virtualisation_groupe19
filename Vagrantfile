# -*- mode: ruby -*-
require 'yaml'
require 'fileutils'

# --- Lecture du fichier .env (les secrets restent hors du dépôt, R7) ---
VARS = {}
fichier_env = File.exist?(".env") ? ".env" : ".env.exemple"
puts "ATTENTION : .env absent, utilisation de .env.exemple" if fichier_env == ".env.exemple"
File.readlines(fichier_env).each do |ligne|
  ligne = ligne.strip
  next if ligne.empty? || ligne.start_with?("#")
  cle, valeur = ligne.split("=", 2)
  VARS[cle] = valeur
end

# --- Paramètres (une variable d'environnement l'emporte sur le .env) ---
GROUPE = (ENV['GROUPE'] || VARS['GROUPE'] || 1).to_i
NB_APP = (ENV['NB_APP'] || VARS['NB_APP'] || 2).to_i
abort "GROUPE doit etre compris entre 1 et 8" unless (1..8).include?(GROUPE)
abort "NB_APP doit etre compris entre 2 et 9" unless (2..9).include?(NB_APP)

RESEAU = "192.168.#{55 + GROUPE}"
BOITE   = "bento/ubuntu-24.04"
VERSION = "202404.26.0"

# Variables transmises aux scripts de provisionnement
VARS["NB_APP"]   = NB_APP.to_s
VARS["DB_HOSTS"] = "#{RESEAU}.31,#{RESEAU}.32"
VARS["APP_PORT"] ||= "3000"

# --- Source unique de vérité : la table des noeuds ---
NOEUDS = []
NOEUDS << { nom: "bdd1", ip: "#{RESEAU}.31", mem: 768, role: "bdd" }
NOEUDS << { nom: "bdd2", ip: "#{RESEAU}.32", mem: 768, role: "replique" }
(1..NB_APP).each do |i|
  NOEUDS << { nom: "app#{i}", ip: "#{RESEAU}.#{20 + i}", mem: 512, role: "app" }
end
NOEUDS << { nom: "lb1", ip: "#{RESEAU}.11", mem: 512, role: "lb" }

# binwrite : garde des fins de ligne LF meme sous Windows
FileUtils.mkdir_p("config")
File.binwrite("config/noeuds.yml", NOEUDS.map { |n| n.transform_keys(&:to_s) }.to_yaml)

Vagrant.configure("2") do |config|
  config.vm.box = BOITE
  config.vm.box_version = VERSION
  config.vm.box_check_update = false

  NOEUDS.each do |n|
    config.vm.define n[:nom] do |m|
      m.vm.hostname = n[:nom]
      m.vm.network "private_network", ip: n[:ip]

      # R8 : seul le répartiteur expose un port vers l'hote
      m.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1" if n[:role] == "lb"

      m.vm.provider "virtualbox" do |vb|
        vb.name   = "g#{GROUPE}-#{n[:nom]}"
        vb.memory = n[:mem]
        vb.cpus   = 1
      end

      # Un script par rôle ; ignoré s'il n'existe pas encore (travail en parallèle)
      script = "scripts/#{n[:role]}.sh"
      m.vm.provision "shell", path: script, env: VARS if File.exist?(script)
    end
  end
end
#!/usr/bin/env python3
"""RÉSULTATS-BF — service applicatif sans état.
GET /resultat?matricule=N -> résultat (JSON) | GET /sante -> 200 si la base
répond, 503 sinon | GET /info -> nom d'hôte. Aucun état local : chaque requête
ouvre sa propre connexion (retirer ou ajouter un serveur reste indolore)."""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import psycopg2

DB = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": int(os.environ.get("DB_PORT", "5432")),
    "dbname": os.environ.get("DB_NAME", "resultats"),
    "user": os.environ.get("DB_USER", "resultats"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "connect_timeout": 3,
}
PORT = int(os.environ.get("APP_PORT", "3000"))


def requete(sql, params=()):
    """Connexion fraîche, une requête, première ligne du résultat."""
    connexion = psycopg2.connect(**DB)
    try:
        with connexion.cursor() as curseur:
            curseur.execute(sql, params)
            return curseur.fetchone()
    finally:
        connexion.close()


class Traitement(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reponse(self, code, objet):
        corps = json.dumps(objet, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/sante":
            self.sante()
        elif url.path == "/info":
            self.reponse(200, {"hote": socket.gethostname()})
        elif url.path == "/resultat":
            self.resultat(parse_qs(url.query))
        else:
            self.reponse(404, {"erreur": "route inconnue"})

    def sante(self):
        """Sonde du répartiteur : 200 seulement si la base répond vraiment."""
        try:
            requete("SELECT 1")
            self.reponse(200, {"statut": "ok", "base": "accessible"})
        except Exception:
            self.reponse(503, {"statut": "ko", "base": "inaccessible"})

    def resultat(self, parametres):
        matricule = (parametres.get("matricule") or [""])[0].strip()
        if not matricule.isdecimal() or len(matricule) > 18:
            return self.reponse(400, {"erreur": "matricule invalide (chiffres attendus)"})
        try:
            ligne = requete(
                "SELECT matricule, nom, serie, moyenne, admis "
                "FROM resultats WHERE matricule = %s", (int(matricule),))
        except Exception:
            return self.reponse(503, {"erreur": "base inaccessible"})
        if ligne is None:
            return self.reponse(404, {"erreur": "matricule inconnu"})
        self.reponse(200, {"matricule": ligne[0], "nom": ligne[1], "serie": ligne[2],
                           "moyenne": float(ligne[3]), "admis": bool(ligne[4])})

    def log_message(self, *args):
        """Pas de journal par requête (bruit et charge inutiles)."""


if __name__ == "__main__":
    # 0.0.0.0 : un service sur 127.0.0.1 n'est joignable que par lui-même.
    ThreadingHTTPServer(("0.0.0.0", PORT), Traitement).serve_forever()

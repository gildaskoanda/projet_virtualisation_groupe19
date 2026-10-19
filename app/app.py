#!/usr/bin/env python3
"""RÉSULTATS-BF — service applicatif sans état.

Endpoints :
  GET /resultat?matricule=NNN  -> résultat du candidat (JSON)
  GET /sante                   -> 200 si la base répond, 503 sinon
  GET /info                    -> hôte qui a répondu
Contrainte structurante : aucun état local, toute connexion est ouverte à la
demande. C'est ce qui rend l'ajout ou le retrait d'un serveur indolore.
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import psycopg2

# Configuration lue dans l'environnement (fourni par /etc/default/resultats).
DB_CFG = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": 5432,
    "dbname": os.environ.get("DB_NAME", "resultats"),
    "user": os.environ.get("DB_USER", "resultats"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "connect_timeout": 3,
}


def connexion_base():
    """Ouvre une connexion fraîche : pas de pool, pas d'état entre requêtes."""
    return psycopg2.connect(**DB_CFG)


class Traitement(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reponse(self, code, objet):
        corps = json.dumps(objet, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/sante":
            self._sante()
        elif url.path == "/info":
            self._reponse(200, {"hote": socket.gethostname()})
        elif url.path == "/resultat":
            self._resultat(url)
        else:
            self._reponse(404, {"erreur": "route inconnue"})

    def _sante(self):
        """La sonde que le répartiteur interroge. Jamais 200 par principe."""
        try:
            connexion = connexion_base()
            curseur = connexion.cursor()
            curseur.execute("SELECT 1")
            curseur.fetchone()
            connexion.close()
            self._reponse(200, {"statut": "ok", "base": "accessible"})
        except Exception:
            self._reponse(503, {"statut": "ko", "base": "inaccessible"})

    def _resultat(self, url):
        matricule = (parse_qs(url.query).get("matricule") or [""])[0].strip()
        if not matricule.isdigit():
            self._reponse(400, {"erreur": "matricule invalide (chiffres attendus)"})
            return
        try:
            connexion = connexion_base()
            curseur = connexion.cursor()
            curseur.execute(
                "SELECT matricule, nom, serie, moyenne, admis "
                "FROM resultats WHERE matricule = %s",
                (int(matricule),),
            )
            ligne = curseur.fetchone()
            connexion.close()
        except Exception:
            self._reponse(503, {"erreur": "base inaccessible"})
            return
        if ligne is None:
            self._reponse(404, {"erreur": "matricule inconnu"})
            return
        self._reponse(
            200,
            {
                "matricule": ligne[0],
                "nom": ligne[1],
                "serie": ligne[2],
                "moyenne": float(ligne[3]),
                "admis": bool(ligne[4]),
            },
        )

    def log_message(self, *args):
        """Pas de logs en sortie standard systématiques (bruit + charge)."""
        pass


if __name__ == "__main__":
    # Écoute sur 0.0.0.0 : un service sur 127.0.0.1 n'est joignable par
    # personne d'autre que lui-même (piège n°1 du projet).
    ThreadingHTTPServer(("0.0.0.0", 8080), Traitement).serve_forever()

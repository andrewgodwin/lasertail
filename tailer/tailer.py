#!/usr/bin/env python

import time
import os
import re
import json
import threading
import subprocess


class Tailer(object):
    """
    Small HTTP server which serves HTTP hits from a file as
    JSON on a pollable endpoint.
    """

    timeout = 30

    ipv4_format = re.compile(r'\d+\.\d+\.\d+\.\d+')
    log_format = re.compile(r'''
        ^
        (\S+) \s+  # client
        (\S+) \s+  # ident
        (\S+) \s+  # http username
        \[([^\]]*)\] \s+  # timestamp
        \"([^\"]*)\" \s+  # HTTP request
        (\d+) \s+  # response code
        (\d+) \s+  # response size
        \"([^\"]*)\" \s+  # referrer
        \"([^\"]*)\" \s+  # user agent
    ''', re.VERBOSE)

    def __init__(self, settings):
        self.lines = []
        self.hosts = settings.get("HOSTS", [])
        self.readers = [
            LineReader(
                setting['host'],
                setting['file'],
                setting.get('key', None),
                self
            )
            for setting in self.hosts
        ]
        self.trim_query_strings = settings.get("TRIM_QUERY_STRINGS", True)
        self.ips_as_subnets = settings.get("IPS_AS_SUBNETS", True)
        self.url_renames = settings.get("URL_RENAMES", [])
        [reader.start() for reader in self.readers]

    def consume_line(self, line):
        # Remove old lines
        while self.lines and self.lines[0][0] < (time.time() - self.timeout):
            self.lines = self.lines[1:]
        # Add the new line
        match = self.log_format.search(line)
        if not match:
            print "Bad line: %s" % line
            return
        client, ident, http_user, timestamp, request, status, size, referrer, user_agent = match.groups()
        # Get the path
        try:
            path = request.split()[1]
        except IndexError:
            return
        if self.trim_query_strings:
            path = path.split("?")[0]
        # Apply any URL renames
        for pattern, sub in self.url_renames.items():
            path = re.sub(pattern, sub, path)
        # If subnets is on, trim the last octet of the IP
        if self.ips_as_subnets and self.ipv4_format.match(client):
            client = client[:client.rindex(".")] + ".*"
        self.lines.append((time.time(), {"host": client, "url": path, "status": int(status), "size": int(size)}))

    def lines_since(self, since=None):
        since = since or (time.time() - 10)
        for timestamp, details in self.lines:
            if timestamp > since:
                yield details

    def __call__(self, environ, start_response):
        # Return the lines since the last call
        try:
            since = float(environ['QUERY_STRING'].split("=")[1])
        except ValueError:
            since = time.time()
        start_response('200 OK', [
            ('Content-Type', 'application/json'),
            ('Access-Control-Allow-Origin', '*'),
        ])
        yield json.dumps({
            "since": time.time(),
            "hits": list(self.lines_since(since)),
        })


class LineReader(threading.Thread):

    def __init__(self, host, file, key, tailer):
        threading.Thread.__init__(self)
        self.host = host
        self.file = file
        self.key = key
        self.tailer = tailer

    def run(self):
        command = ["ssh", self.host, "tail -f %s" % self.file]
        if self.key:
            command.insert(1, "-i")
            command.insert(2, self.key)
        proc = subprocess.Popen(command, stdout=subprocess.PIPE)
        for line in iter(proc.stdout.readline, ""):
            tailer.consume_line(line)


def decode_host(host):
    host, filename = host.split(":", 1)
    if "?" in host:
        host, key = host.split("?", 1)
    else:
        key = None
    return host, filename, key


# I know I shouldn't use execfile. So sue me.
settings_file = os.environ.get('LASERTAIL_SETTINGS', "lasertail_settings.py")
settings = {}
execfile(settings_file, {}, settings)
tailer = Tailer(settings)

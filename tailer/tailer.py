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
    format = re.compile(r'''
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

    def __init__(self, hosts, port=8421):
        self.lines = []
        self.hosts = hosts
        self.port = port
        self.readers = [LineReader(host, file, key, self) for host, file, key in hosts]
        [reader.start() for reader in self.readers]

    def consume_line(self, line):
        # Remove old lines
        while self.lines and self.lines[0][0] < (time.time() - self.timeout):
            self.lines = self.lines[1:]
        # Add the new line
        match = self.format.search(line)
        if not match:
            print "Bad line: %s" % line
            return
        client, ident, http_user, timestamp, request, status, size, referrer, user_agent = match.groups()
        try:
            path = request.split()[1]
        except IndexError:
            return
        self.lines.append((time.time(), {"host": client, "url": path}))

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

tailer = Tailer([decode_host(host) for host in os.environ['LASERTAIL_HOSTS'].split(";")])

#!/usr/bin/env python

import sys
import json
import os
import subprocess
import re

try:
  # For python3
  import urllib.request
except ImportError:
  # For python2
  import imp
  import urllib2
  urllib = imp.new_module('urllib')
  urllib.request = urllib2

for change in sys.argv[1:]:
    print(change)
    f = urllib.request.urlopen('http://yauniks.dynvpn.de/query?q=change:%s' % change)
    d = f.read().decode(encoding='UTF-8')
    # gerrit doesnt actually return json. returns two json blobs, separate lines. bizarre.
    print(d)
    d = d.split('\n')[0]
    data = json.loads(d)
    project = data['project']

    plist = subprocess.Popen([os.environ['HOME']+"/bin/repo","list"], stdout=subprocess.PIPE)
    while(True):
        retcode = plist.poll()
        pline = plist.stdout.readline().rstrip()
        ppaths = re.split('\s*:\s*', pline.decode())
        if ppaths[1] == project:
            project = ppaths[0]
            break
        if(retcode is not None):
            break

    print(project)
    number = data['number']

    f = urllib.request.urlopen("http://yauniks.dynvpn.de/changes/%s/revisions/current/review" % number)
    d = f.read()
    d = '\n'.join(d.split('\n')[1:])
    data = json.loads(d)

    current_revision = data['current_revision']
    patchset = 0
    ref = ""

    for i in data['revisions']:
        if i == current_revision:
            ref = data['revisions'][i]['fetch']['anonymous http']['ref']
            patchset = data['revisions'][i]['_number']
            break

    print("Patch set: %i" % patchset)
    print("Ref: %s" % ref)

    if not os.path.isdir(project):
        sys.stderr.write('no project directory: %s' % project)
        sys.exit(1)

    os.system('cd %s ; git fetch  http://yauniks.dynvpn.de/%s %s' % (project, data['project'], ref))
    os.system('cd %s ; git merge FETCH_HEAD' % project)

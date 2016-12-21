#!/usr/bin/env python
import os
from collections import Counter, defaultdict
import json
import argparse
import psycopg2
import psycopg2.extras
import mwparserfromhell
from mwparserfromhell.nodes.wikilink import Wikilink

INFOBOX_PREFIX = 'infobox '
CATEGORY_PREFIX = 'category:'

BLACK_LIST = {'Israeli art'}

def extract_artworks(wiki_text):
  p = 0
  res = []
  while True:
    p = wiki_text.find('<gallery', p)
    if p == -1:
      break
    p = wiki_text.find('>', p)
    if p == -1:
      break
    start = p + 1
    p = wiki_text.find('</gallery', start)
    if p == -1:
      break
    lines = [x.strip() for x in wiki_text[start: p].split('\n') if x.strip()]
    res.extend(line.split('|')[0].strip() for line in lines)
  return res


def stored_json(file_name):
  def decorator(func):
    def new_func(cursor, json_out):
      path = os.path.join(json_out, file_name)
      if os.path.isfile(path):
        res = json.load(file(path))
      else:
        res = func(cursor, json_out)
        json.dump(res, file(path, 'w'))
      return res
    return new_func
  return decorator

#@stored_json('artists.json')
def get_artists(postgres_cursor, json_out):
  artists = []
  postgres_cursor.execute("select * from wikipedia where infobox = 'artist'")
  for artist in postgres_cursor:
    wikicode = mwparserfromhell.parse(artist['wikitext'])
    name = artist['title']
    references = {}

    for template in wikicode.filter_templates():
      name = template.name.strip_code().strip()
      if name.lower() == INFOBOX_PREFIX + artist['infobox']:
        for param in template.params:
          if param.name.strip() == 'name':
            name = param.value.strip_code()
          refs = [unicode(node.title) for node in param.value.filter_wikilinks() if isinstance(node, Wikilink)]
          if refs:
            references[param.name.strip()] = refs
        break

    art_works = extract_artworks(artist['wikitext'])
    artists.append({'name': name,
                    'cats': artist['categories'],
                    'works': references.get('works', []),
                    'movement': references.get('movement', []),
                    'field': references.get('field', []),
                    'art_works': art_works}
                   )
  return artists

def processed_cats(cursor, store, root_cat):
  for title in [cat['title'][len(CATEGORY_PREFIX):].lower() for cat in cursor if cat['title'].lower().startswith(CATEGORY_PREFIX)]:
    store[title] = root_cat

#@stored_json('art_cats.json')
def get_art_cats(postgres_cursor, json_out):
  postgres_cursor.execute("select title from wikipedia where categories @> ARRAY['art movements']")
  root_cats = [cat['title'][len(CATEGORY_PREFIX):].lower() for cat in postgres_cursor if cat['title'].lower().startswith(CATEGORY_PREFIX)]
  root_cats = filter(lambda x: not x in ('paintings by movement or period', 'artists by genry'), root_cats)
  artist_cats = {}
  for rc in root_cats:
    postgres_cursor.execute("select title from wikipedia where general @> ARRAY['artists'] and categories @> ARRAY[%s]", (rc,))
    processed_cats(postgres_cursor, artist_cats, rc)
  painting_cats = {}
  for rc in root_cats:
    postgres_cursor.execute("select title from wikipedia where general @> ARRAY['paintings'] and categories @> ARRAY[%s]", (rc,))
    processed_cats(postgres_cursor, painting_cats, rc)
  return root_cats, artist_cats, painting_cats

@stored_json('paintings.json')
def get_paintings(postgres_cursor, json_out):
  postgres_cursor.execute("select * from wikipedia where general @> ARRAY['paintings']")
  res = []
  for painting in postgres_cursor:
    name = painting['title']
    wiki_id = name
    wikicode = mwparserfromhell.parse(painting['wikitext'])
    image_file = None
    year = None
    for template in wikicode.filter_templates():
      for param in template.params:
        if param.name.strip() == 'image_file':
          image_file = param.value.strip_code()
      if template.name.strip().startswith(INFOBOX_PREFIX):
        if param.name.strip() == 'name':
          name = param.value.strip_code()
        if param.name.strip() == 'year':
          year = param.value.strip_code()
    if image_file:
      res.append({'wiki_id': wiki_id,
                  'name': name,
                  'year': year,
                  'image_file': image_file,
                  'categories': painting['categories']})
  return res



def main(postgres_cursor, json_out):
  root_cats, artist_cats, painting_cats = get_art_cats(postgres_cursor, json_out)
  root_cats = set(root_cats)
  artists = get_artists(postgres_cursor, json_out)
  paintings = get_paintings(postgres_cursor, json_out)
  res = []
  movement_count = Counter()
  for artist in artists:
    movement = set(artist['movement'])
    for cat in artist['cats']:
      if cat in root_cats:
        movement.add(cat)
      if cat in artist_cats:
        movement.add(artist_cats[cat])
    for m in movement:
      movement_count[m] += 1

  artists = filter(lambda a: len(a['movement']) > 0, artists)

  paintings_by_movement = defaultdict(list)
  for artist in artists:
    most_popular_movement = max(artist['movement'], key=lambda m:movement_count[m])
    paintings_by_movement[most_popular_movement].extend(artist['art_works'])

  print sum(len(v) for v in paintings_by_movement.values())
  for k, v in sorted(paintings_by_movement.items(), key=lambda t:len(t[1]), reverse=True)[:20]:
    print k, len(v)

  json.dump(dict(paintings_by_movement), file(os.path.join(json_out, 'paintings_by_movement.json'), 'w'))



if __name__ == '__main__':
  parser = argparse.ArgumentParser(description='Collect painters and their schools')
  parser.add_argument('--postgres', type=str,
                      help='postgres connection string')
  parser.add_argument('json_out', type=str,
                      help='Json file that will hold the result')

  args = parser.parse_args()

  postgres_conn = psycopg2.connect(args.postgres)
  postgres_cursor = postgres_conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

  main(postgres_cursor, args.json_out)





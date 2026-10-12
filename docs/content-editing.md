# Content editing (Sveltia CMS)

Posts and the homepage data can be edited through
[Sveltia CMS](https://sveltiacms.app/) at
<https://nicholas.santiago.wtf/admin/>. It's configured in
[`static/admin/config.yml`](../static/admin/config.yml), and the editor
version is pinned in [`static/admin/index.html`](../static/admin/index.html).

Sveltia has no accounts of its own. It signs in with a code.inl.io (Forgejo)
account, so anyone with write access to `nick/personal-website` can edit.

## Saving and publishing

`main` only accepts pull requests, so the CMS uses Sveltia's
[editorial workflow](https://sveltiacms.app/en/docs/workflows/editorial):

1. **Save** commits the entry to its own branch, `cms/<collection>/<entry>`,
   and opens a pull request for it. Later saves of the same entry add to
   that branch.
2. Woodpecker runs the pull request pipeline: lint, build, and a deploy dry
   run, with the results in a PR comment.
3. Move the entry to **Ready** on the CMS's Workflow board (or from the
   editor's status menu), then **Publish**. That squash-merges the pull
   request and deletes the branch, and the push to `main` deploys.

Publish fails while the pipeline is still running or has failed, and when
`main` has moved on since the branch was made (branch protection requires
an up-to-date branch). For the latter, press **Update branch** on the pull
request, wait for the pipeline, reload the CMS, and publish again.

Images are uploaded from an entry's image fields and go into that entry's
pull request. The Media page can't upload or delete files, since that would
commit straight to `main`.

## What's editable

| Collection        | Files                                                                      |
| ----------------- | -------------------------------------------------------------------------- |
| Posts             | `content/posts/YYYYMMDD_slug.md`; images go to `static/images/posts/`      |
| Profile           | `data/en/author.yaml`, `data/en/site.yaml`                                 |
| Homepage Sections | `data/en/sections/*.yaml` (about, skills, experiences, projects, and more) |

Uploads are converted to WebP, capped at 2400px, and renamed to lowercase
with underscores (`My Photo.jpg` becomes `my_photo.webp`).

## What a CMS save changes

Sveltia rewrites the whole file it saves, so the first save of each file
also:

- **Drops YAML comments**, including commented-out front matter such as
  `# hero: ...`.
- **Normalizes YAML:** it removes unneeded quotes, unwraps long strings onto
  one line, and adds `hideTitle: false` to homepage sections.

The rendered site doesn't change. Keep notes and commented-out alternatives
in Git history or this file instead of in the data files.

The post body uses the plain Markdown editor only. Sveltia's rich text
editor rewrites the whole body on save, indenting nested lists by 4 spaces
and escaping `~`. That fails markdownlint, which would block the deploy.

Sveltia single-quotes YAML strings that need quotes (for example a title
containing a colon), which Prettier would change to double quotes. For that
reason the Prettier check only reports on CMS pull requests (`cms/...`
branches) and on pushes to `main`, and blocks other pull requests. Run `npx prettier@3.9.10 --write .` after pulling to tidy up.

## Local testing

Run `hugo server -D`, then open <http://localhost:1313/admin/> in Chrome or
Edge and choose **Work with Local Repository**. Pick this checkout, and
allow Chrome to edit files when it first saves. Edits are written to disk
without being committed, and there's no workflow board.

## Forge setup

`/admin/` needs two things on code.inl.io:

1. **A non-confidential OAuth2 application** with these redirect URIs:
   - `https://nicholas.santiago.wtf/admin/`
   - `http://localhost:1313/admin/`

   Its Client ID is `app_id` in `static/admin/config.yml`. It's public by
   design: PKCE needs no client secret.

   CloudFront redirects `/admin` to `/admin/` (`cloudfront_index_redirect`
   on the site's module in inl-io/tofu), so the CMS always runs at
   `/admin/`. Without that redirect it would load `/config.yml` and send an
   unregistered redirect URI.

2. **CORS for the site's origin.** `https://nicholas.santiago.wtf` has to be
   listed in `gitea.config.cors.ALLOW_DOMAIN` in
   [`forgejo-app.yaml`](https://github.com/inl-io/argo-apps/blob/main/clusters/inl-k8s-blue-config/values/workloads/forgejo-app.yaml)
   in inl-io/argo-apps. Merging there syncs and restarts Forgejo.

If the site moves to a new URL, add its `/admin/` URLs to the OAuth app,
add its origin to `ALLOW_DOMAIN`, and update `site_url` in `config.yml`.

# Nick's Personal Website

[![CI status](https://ci.inl.io/api/badges/1/status.svg?branch=main)](https://ci.inl.io/repos/1)

Source for **<https://nicholas.santiago.wtf/>**, a static site built with
[Hugo](https://gohugo.io) and the [Toha](https://github.com/hugo-toha/toha)
theme, hosted on S3 behind CloudFront.

## Where things live

| Path | What's in it |
|---|---|
| [`config.yml`](config.yml) | Hugo config: site params, menus, and the `production` deploy target (S3 bucket + CloudFront distribution) |
| [`data/en/author.yaml`](data/en/author.yaml) | Name, contact info, and summary shown in the sidebar/hero |
| [`data/en/sections/`](data/en/sections) | Homepage sections: about, experiences, skills, projects, achievements, recent posts |
| [`content/posts/`](content/posts) | Blog posts, one Markdown file each (`YYYYMMDD_slug.md`) |
| [`static/`](static) | Files served as-is: images, `files/` (resume PDF/ODT, certs), `resume.json` |
| [`themes/toha/`](themes/toha) | Vendored copy of the Toha theme, with local tweaks — edit it here, not upstream |
| [`.woodpecker/deploy.yaml`](.woodpecker/deploy.yaml) | CI/CD pipeline (see [Deployment](#deployment)) |

## Local development

Requires Hugo **extended**, ideally the version pinned in
[`.woodpecker/deploy.yaml`](.woodpecker/deploy.yaml) (currently 0.166.0).

```sh
hugo server -D        # live-reloading preview at http://localhost:1313, drafts included
```

To preview the production build the way the container image serves it (nginx
on port 8080):

```sh
./local.sh            # podman build + run, then open http://localhost:8080
```

### Writing a post

```sh
hugo new content posts/20261001_my_post.md
```

Then fill in the front matter: the generated `title` is just the filename, and
posts start as `draft: true` (flip it to publish). The sidebar
lists them by `menu.sidebar.weight`, lowest first, so give a new post a lower
weight than the current newest one (e.g. `-8` after `-7`):

```yaml
hero: /images/posts/20261001_my_post_masthead.png
description: One-line summary shown in post listings.
menu:
  sidebar:
    name: "Short sidebar title"
    identifier: my-post
    weight: -8
```

## Deployment

Deploys run on [Woodpecker CI](https://ci.inl.io/repos/1) using the official
`ghcr.io/gohugoio/hugo` image:

| Event | What happens |
|---|---|
| Pull request to `main` | Build the site, run `hugo deploy --dryRun`, and post (or update) a 🚀 deploy-preview comment on the PR listing every file that would upload or be deleted |
| Push to `main` | Build the site and `hugo deploy` to S3; Hugo invalidates the CloudFront cache when anything changed |

Site settings and secrets are grouped at the top of the pipeline under
`variables:`. The pipeline needs these Woodpecker secrets:

| Secret | Scope | Used for |
|---|---|---|
| `aws_access_key_id`, `aws_secret_access_key`, `aws_default_region` | repo | `hugo deploy` to S3 + CloudFront |
| `forgejo-devops-bot-token` | global | Posting the PR comment as `devops-bot` |

For a manual deploy from a workstation with AWS credentials loaded,
[`deploy.sh`](deploy.sh) builds and deploys in one go (`./deploy.sh [target]`).

## Dependencies

[Renovate](renovate.json5) (run from
[`.forgejo/workflows/renovate.yaml`](.forgejo/workflows/renovate.yaml)) opens
PRs to bump Hugo, the pipeline images, and the theme's npm packages.

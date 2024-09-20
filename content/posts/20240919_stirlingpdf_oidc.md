---
title: "Fun with Stirling PDF, Portainer and OIDC"
date: 2024-09-19T00:00:00-04:00
draft: false
hero: /images/posts/20240919_stirling_pdf_masthead.png
description: Though generally easy, OIDC gotchas apply with this app.
menu:
  sidebar:
    name: "Stirling PDF with OIDC"
    identifier: stirling-pdf-portainer-oidc
    weight: -7
tags:
  - docker
  - jumpcloud
  - oauth2
  - oidc
  - pdf
  - podman
  - portainer
  - sso
  - stirling_pdf
---

I've spent more time messing around with [Stirling PDF](https://github.com/Stirling-Tools/Stirling-PDF.git) and its new authentication feature over the past couple of days than I care to admit, and need to brain dump what I came up with.

So, some background first. Authentication for my homelab is currently run by [Jumpcloud](https://jumpcloud.com), since they're the best bang for buck for my small environment (~4 users). They give me a user portal, support SAML and OIDC SSO, have an LDAP connector in case I have legacy stuff that need that, and there's a [somewhat useful Terraform module](https://registry.terraform.io/providers/Paynetworx/jumpcloud/), albeit incomplete.

> I should note that this isn't a criticism of Stirling PDF, Jumpcloud or the community members that made the Terraform module, but rather just a story of a mental block caused by my own paradigm paralysis and auto-pilot. In fact, I enjoy these tools so much that I'm signal boosting them on a blog that gets _tens_ of views every year.

Anyway - all of that should work fine with Stirling PDF, now that there is OAuth2 capability since [v0.24.0](https://github.com/Stirling-Tools/Stirling-PDF/releases/tag/v0.24.0). I figured that I would just get the redirect URIs, login URL, exchange client key and secret, and be done. Nope.

I was met with weird errors all the way through, from the app not properly bootstrapping to environment vars being quoted when they shouldn't, so here's how I got it to work with Jumpcloud.

## The Problem

Once I figured out which variables were easier to define via environment vars versus populating the custom config file, I was getting 401 errors back in a gnarly looking stack trace once users federated in. This is an example of the trace:

```plain
2024-09-20 03:45:42,203 INFO s.s.S.c.s.s.CustomHttpSessionListener [qtp197711499-30] Session created: node0wmxprzcn9jzv1kmg3ww3q74rb0
2024-09-20 03:46:14,820 ERROR s.s.S.c.s.o.CustomOAuth2AuthenticationFailureHandler [qtp197711499-51] OAuth2 Authentication error: invalid_token_response
2024-09-20 03:46:14,821 ERROR s.s.S.c.s.o.CustomOAuth2AuthenticationFailureHandler [qtp197711499-51] OAuth2AuthenticationException
org.springframework.security.oauth2.core.OAuth2AuthenticationException: [invalid_token_response] An error occurred while attempting to retrieve the OAuth 2.0 Access Token Response: 401 Unauthorized: [no body]
 ... snip ...
Caused by: org.springframework.security.oauth2.core.OAuth2AuthorizationException: [invalid_token_response] An error occurred while attempting to retrieve the OAuth 2.0 Access Token Response: 401 Unauthorized: [no body]
 ... snip ...
Caused by: org.springframework.web.client.HttpClientErrorException$Unauthorized: 401 Unauthorized: [no body]
 ... snip ...
2024-09-20 03:46:14,900 INFO s.s.S.c.s.s.CustomHttpSessionListener [qtp197711499-59] Session destroyed: node0wmxprzcn9jzv1kmg3ww3q74rb0
```

(Yes, I know stack traces are ugly, but I'm leaving the key pieces in for searchability, that way I can help someone else that goes through this.)

Long story short, when a user logs in, Stirling PDF reaches out to Jumpcloud to get a token to authenticate the user, and it uses a client ID and client secret to authenticate itself. But we get an `HTTP 401`, and I couldn't figure out why. Turns out that I was using the wrong type of authentication.

Instead of doing a request in the HTTP body, which is the default behavior when setting up an OIDC application, Stirling PDF is looking to do a basic authentication. Jumpcloud describes what this does [in their OIDC documentation](https://jumpcloud.com/support/sso-with-oidc#endpoint-configuration) better than I ever could.

![Screenshot of Jumpcloud admin portal, showing OIDC client authentication types](/images/posts/20240919_jumpcloud_oidc_authtype.png)

We're going to go step-by-step through the process below, but that's the gist of the gotcha that I ran into.

## Portainer

Since I'm not ready to move this into Kubernetes yet, this is running as a single container on my Portainer instance. It's fine. It's whatever. Anyway, the Portainer stack definition is configured like so:

```yaml
---
version: "3.3"
services:
  stirling-pdf:
    image: docker.io/frooodle/s-pdf:0.29.0
    ports:
      - "18080:8080"
    volumes:
      - /mnt/nas/pdftools-tessdata:/usr/share/tessdata
      - /mnt/nas/pdftools-config:/configs
      - /mnt/nas/pdftools-customfiles:/customFiles/
      - /mnt/nas/pdftools-logs:/logs/
    environment:
      INSTALL_BOOK_AND_ADVANCED_HTML_OPS: "true"
      LANGS: en_US
      TZ: Etc/UTC
      DOCKER_ENABLE_SECURITY: "true"
```

That local port of `18080` is being fronted by a Cloudflare Tunnel so that I don't have to worry about TLS, port forwarding, and the like. And you might say "hey, if you're using Cloudflare, couldn't use that to authenticate this app?" The simple answer is yes, and the complicated answer is "I didn't think about that until this very moment."

If you start this stack up as-is, the app should come up and just be unauthenticated, but have pulled the additional JAR for OIDC support. This is fine for now, as we'll add the custom config later.

## Jumpcloud

This is the part that messed me up. I did a very typical OIDC app, like I've done it a zillion of times before.

From the [Admin Console](https://console.jumpcloud.com/#/applications) > **SSO Applications** > **Add new application** > **Custom application** > **Manage SSO** > **Configure SSO with OIDC**.

I'm going to give you the `tl;dr` of this so that you don't have to get 401s all over the place every time someone authenticates. But if you're getting 401s, odds are that your Client Authentication Type is set to _Client Secret Post_ instead of **Client Secret Basic**. As soon as I changed this param, I was off to the races.

So, here's my entire Jumpcloud app config:

- **General Info**
  - **Application Name**: Stirling PDF
  - **Description**: (blank)
  - **Display Option**: Logo
  - **Logo**: [Stirling Logo](/images/posts/20240919_stirling_pdf_logo.png)
  - **Show application in user portal**: true
- **SSO**
  - **Grant Types**
    - **Refresh Token**: false
    - **Client ID**: UUID generated by Jumpcloud
    - **Redirect URIs**:
      - `https://${MY_STIRLING_PDF_FQDN}/login/oauth2/code/oidc`
    - **Client Authentication Type**: Client Secret Basic
    - **Login URL**: `https://${MY_STIRLING_PDF_FQDN}/oauth2/authorization/oidc`
    - **Attribute Mapping**
      - **Standard Scopes**
        - **Email**: true
        - **Profile**: true (I don't think the app is actually using this, but I have it turned on just in case it wants to do a pretty display name at some point)
      - **User Attribute Mapping** (only one of these matters right now)
        - SP: email  
          IDP: email
      - **Group Attributes**: false
    - **Identity Management** (SCIM)
      - Nothing to enable here, just leave as-is
    - **User Groups**: assign whichever groups you want

So, you're going to be handed a client secret, which you'll be placing into a configuration YAML and with which you'll be restarting the app.

## Stirling PDF Custom Settings

As I understand it, Stirling PDF merges its default `settings.yml` and `custom_settings.yml`, so you don't have to define _everything_ in your custom settings, only the things you want to change.

Mine looks like this:

```yaml
---
security:
  enableLogin: true # set to 'true' to enable login
  csrfDisabled: false # Set to 'true' to disable CSRF protection (not recommended for production)
  loginAttemptCount: 5 # lock user account after 5 tries; when using e.g. Fail2Ban you can deactivate the function with -1
  loginResetTimeMinutes: 120 # lock account for 2 hours after x attempts
  loginMethod: oauth2 # 'all' (Login Username/Password and OAuth2[must be enabled and configured]), 'normal'(only Login with Username/Password) or 'oauth2'(only Login with OAuth2)
  oauth2:
    enabled: true # set to 'true' to enable login (Note: enableLogin must also be 'true' for this to work)
    issuer: "https://oauth.id.jumpcloud.com/" # set to any provider that supports OpenID Connect Discovery (/.well-known/openid-configuration) end-point
    clientId: "8b1ec1c6-767f-11ef-8e9c-84a9387233fb" # Client ID from your provider
    clientSecret: "REDACTED" # Client Secret from your provider
    autoCreateUser: true # set to 'true' to allow auto-creation of non-existing users
    blockRegistration: false # set to 'true' to deny login with SSO without prior registration by an admin
    useAsUsername: email # Default is 'email'; custom fields can be used as the username
    scopes: openid, profile, email # Specify the scopes for which the application will request permissions
    provider: oidc # Set this to your OAuth provider's name, e.g., 'google' or 'keycloak'

ui:
  appName: "Stirling PDF" # Application's visible name
  homeDescription: "Running within the confines of my basement" # Short description or tagline shown on homepage.
  appNameNavbar: "Stirling PDF" # Name displayed on the navigation bar
```

As soon as that `custom_settings.yml` file is saved in whatever path the container will have mapped to `/configs`, you should be all set. Restart the container(or the whole stack, doesn't matter), and then you should be off to the races.

**Happy PDFing!**

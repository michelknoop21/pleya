<script lang="ts">
  import Logo from './Logo.svelte';
  import { SOURCE_REPO_URL } from '$lib/config';

  const year = new Date().getFullYear();
</script>

<footer class="site-footer">
  <div class="footer-inner">
    <!-- Gradient rule -->
    <div class="gradient-rule"></div>

    <div class="footer-content">
      <!-- Logo + name -->
      <div class="footer-brand">
        <span class="footer-logo"><Logo alt="Pleya" /></span>
        <span>Pleya</span>
      </div>

      <!-- Links -->
      <nav class="footer-nav">
        <a href="/privacy">Privacy Policy</a>
        <a href={SOURCE_REPO_URL} target="_blank" rel="noopener noreferrer">Source</a>
      </nav>
    </div>

    <div class="footer-meta">
      <p class="footer-copy">© {year} Michel Knoop</p>
      <p class="footer-credit">
        Based on
        <a href={SOURCE_REPO_URL} target="_blank" rel="noopener noreferrer">Plezy (GPL-3.0)</a>.
      </p>
    </div>
  </div>
</footer>

<style>
  .site-footer {
    padding: 2.5rem 1.5rem;
  }

  .footer-inner {
    max-width: 64rem;
    margin-inline: auto;
  }

  .gradient-rule {
    height: 1px;
    margin-bottom: 2rem;
    background: linear-gradient(to right, transparent, var(--color-border), transparent);
  }

  .footer-content {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: space-between;
    gap: 1.5rem;
  }

  .footer-brand {
    display: flex;
    align-items: center;
    gap: 0.625rem;
    color: var(--color-text-muted);
    font-weight: 600;
  }

  .footer-logo :global(img) {
    width: 1.75rem;
    height: 1.75rem;
  }

  .footer-nav {
    display: flex;
    align-items: center;
    gap: 2rem;
    color: var(--color-text-muted);
    font-size: 0.875rem;
    line-height: 1.25rem;
  }

  .footer-nav a {
    transition: color 150ms ease;
  }

  .footer-nav a:hover {
    color: var(--color-text);
  }

  .footer-meta {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.375rem;
    margin-top: 2rem;
    color: var(--color-text-faint);
    font-size: 0.8125rem;
    text-align: center;
  }

  .footer-credit a {
    color: var(--color-text-muted);
    text-decoration: underline;
    text-underline-offset: 2px;
    transition: color 150ms ease;
  }

  .footer-credit a:hover {
    color: var(--color-text);
  }

  @media (min-width: 640px) {
    .site-footer {
      padding-block: 4rem;
    }

    .gradient-rule {
      margin-bottom: 3rem;
    }

    .footer-content {
      flex-direction: row;
    }

    .footer-meta {
      flex-direction: row;
      justify-content: space-between;
    }
  }
</style>

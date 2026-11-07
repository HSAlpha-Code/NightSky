from django.db import models


class CuratedHighlight(models.Model):
    """A hand-picked, pre-rendered image for one celestial body.

    `body_id` is the landmark id used by /api/landmarks (e.g. "NGC1976", "HIP26311").
    The image is a local file (see settings.CURATED_MEDIA_ROOT / the exported bundle); the
    backend never fetches anything from the news outlet at request time.
    """
    body_id = models.CharField(max_length=64, db_index=True)
    body_name = models.CharField(max_length=200)
    title = models.CharField(max_length=200, blank=True)
    image_file = models.CharField(max_length=200, help_text="File name inside the image folder.")
    source_outlet = models.CharField(max_length=100, blank=True, help_text="e.g. NASA, ESA, BBC")
    source_url = models.URLField(max_length=500, blank=True)
    credit = models.CharField(max_length=300, blank=True, help_text="Credit / copyright note")
    caption = models.TextField(blank=True)
    ra = models.FloatField(null=True, blank=True)
    dec = models.FloatField(null=True, blank=True)
    enabled = models.BooleanField(default=True)
    sort_order = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["body_id", "sort_order", "id"]

    def __str__(self) -> str:
        return f"{self.body_name}: {self.title or self.image_file}"

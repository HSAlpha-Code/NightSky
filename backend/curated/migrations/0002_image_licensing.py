from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("curated", "0001_initial")]
    operations = [
        migrations.AddField(model_name="curatedhighlight", name="license_name",
                            field=models.CharField(blank=True, max_length=150)),
        migrations.AddField(model_name="curatedhighlight", name="license_url",
                            field=models.URLField(blank=True, max_length=500)),
        migrations.AddField(model_name="curatedhighlight", name="modifications",
                            field=models.TextField(blank=True, help_text="Known changes to the source image")),
    ]

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("curated", "0002_image_licensing")]
    operations = [
        migrations.AddField(
            model_name="curatedhighlight", name="source_link_text",
            field=models.CharField(
                blank=True, max_length=200,
                help_text="Text shown for the source link in the app (default: the outlet name)")),
    ]

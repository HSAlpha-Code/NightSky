from rest_framework import serializers


class QuaternionSerializer(serializers.Serializer):
    x = serializers.FloatField()
    y = serializers.FloatField()
    z = serializers.FloatField()
    w = serializers.FloatField()


class OrientationSerializer(serializers.Serializer):
    quaternion = QuaternionSerializer(required=False)
    rotation_matrix = serializers.ListField(child=serializers.FloatField(), min_length=9,
                                            max_length=9, required=False)
    reference = serializers.ChoiceField(choices=["true_north", "magnetic_north"],
                                        default="magnetic_north")

    def validate(self, attrs):
        if "quaternion" not in attrs and "rotation_matrix" not in attrs:
            raise serializers.ValidationError("Provide quaternion or rotation_matrix.")
        return attrs


class SolveMetadataSerializer(serializers.Serializer):
    latitude = serializers.FloatField(min_value=-90, max_value=90, required=False)
    longitude = serializers.FloatField(min_value=-180, max_value=180, required=False)
    altitude = serializers.FloatField(required=False, default=0.0)
    timestamp = serializers.DateTimeField(required=False)
    orientation = OrientationSerializer(required=False)
    image_rotation_deg = serializers.ChoiceField(choices=[0, 90, 180, 270], default=0)
    fov_deg = serializers.FloatField(min_value=1, max_value=120, required=False)


class SolveRequestSerializer(serializers.Serializer):
    image = serializers.FileField()
    metadata = serializers.JSONField(binary=True, required=False, default=dict)

    def validate_metadata(self, value):
        s = SolveMetadataSerializer(data=value)
        s.is_valid(raise_exception=True)
        return s.validated_data


class SolveResponseSerializer(serializers.Serializer):
    ra = serializers.FloatField()
    dec = serializers.FloatField()
    rotation = serializers.FloatField()
    fov = serializers.FloatField()
    confidence = serializers.FloatField()
    approximate = serializers.BooleanField()
    source = serializers.CharField()
    message = serializers.CharField(allow_blank=True)
    alt = serializers.FloatField(allow_null=True)
    az = serializers.FloatField(allow_null=True)
